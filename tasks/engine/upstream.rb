# frozen_string_literal: true

require "net/http"
require "json"
require "digest"
require "rexml/document"
require_relative "version"

module EngineUpdates
  class HTTP
    RETRYABLE = [429, 500, 502, 503, 504].freeze

    def initialize(token: ENV["GH_TOKEN"] || ENV["GITHUB_TOKEN"])
      @token = token
      @cache = {}
    end

    def get(url)
      @cache[url] ||= begin
        body = +""
        request(url) { |chunk| body << chunk }
        body
      end
    end

    def sha256(url)
      digest = Digest::SHA256.new
      request(url) { |chunk| digest.update(chunk) }
      digest.hexdigest
    end

    private

    def request(url, redirects: 5, attempt: 0, &block)
      uri = URI(url)
      raise Error, "Expected an HTTPS URL: #{url}" unless uri.is_a?(URI::HTTPS) && !uri.userinfo

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "images-rb-engine-updater"
      request["Authorization"] = "Bearer #{@token}" if @token && uri.host == "api.github.com"
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        http.max_retries = 0
        http.request(request) do |response|
          code = response.code.to_i
          if RETRYABLE.include?(code) && attempt < 2
            sleep(2**attempt)
            return request(url, redirects: redirects, attempt: attempt + 1, &block)
          end
          if response.is_a?(Net::HTTPRedirection)
            raise Error, "Too many redirects: #{url}" if redirects.zero?

            return request(URI.join(url, response.fetch("location")).to_s, redirects: redirects - 1, &block)
          end
          raise Error, "HTTP #{code}: #{url}" unless response.is_a?(Net::HTTPSuccess)

          response.read_body(&block)
        end
      end
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
      # A partially streamed archive cannot be retried into the same digest.
      raise Error, "Could not fetch #{url}: #{e.message}"
    end
  end

  module Upstream
    def self.for(engine, http: HTTP.new)
      {"ruby" => CRuby, "jruby" => JRuby, "truffleruby" => TruffleRuby}.fetch(engine).new(http)
    end

    class Source
      def initialize(http)
        @http = http
      end

      def checksum(text)
        value = text.to_s.strip
        raise Error, "Invalid SHA-256: #{value.inspect}" unless /\A[0-9a-f]{64}\z/i.match?(value)

        value.downcase
      end

      def resolve(release, required)
        release.assets = required.to_h do |key|
          asset = release.assets.fetch(key) { raise Error, "Missing #{key} archive for #{release.version}" }
          [key, Asset.new(url: asset.url, sha256: checksum(asset.sha256), provenance: asset.provenance)]
        end
        release
      end
    end

    class CRuby < Source
      INDEX = "https://cache.ruby-lang.org/pub/ruby/index.txt"

      def releases
        parse(@http.get(INDEX))
      end

      def parse(text)
        rows = text.lines.map { |line| line.chomp.split("\t") }
        raise Error, "Unexpected Ruby release index header" unless rows.shift == %w[name url sha1 sha256 sha512]

        releases = {}
        rows.each do |name, url, _, sha256, _|
          next unless name&.match?(/\Aruby-\d+\.\d+\.\d/)
          next unless url && (match = /\Ahttps:\/\/cache\.ruby-lang\.org\/pub\/ruby\/[^\/]+\/ruby-(.+)\.(tar\.xz|tar\.gz|tar\.bz2|zip)\z/.match(url))
          next unless name == "ruby-#{match[1]}"

          version = Version.new(match[1])
          release = releases[name] ||= Release.new(version: version, assets: {}, url: INDEX)
          release.assets[match[2]] = Asset.new(url: url, sha256: sha256, provenance: "upstream index")
        end
        raise Error, "Empty Ruby release index" if releases.empty?

        releases.values
      end

      def resolve(release, required)
        super.tap do |resolved|
          resolved.assets.each_value do |asset|
            unless asset.url.include?("/pub/ruby/#{release.version.series}/")
              raise Error, "Ruby archive series does not match #{release.version}: #{asset.url}"
            end
          end
        end
      end
    end

    class JRuby < Source
      ROOT = "https://repo1.maven.org/maven2/org/jruby/jruby-dist"

      def releases
        parse(@http.get("#{ROOT}/maven-metadata.xml"))
      end

      def parse(text)
        document = REXML::Document.new(text)
        raise Error, "Unexpected JRuby metadata" unless document.elements["metadata/artifactId"]&.text == "jruby-dist"

        releases = document.get_elements("metadata/versioning/versions/version").map do |node|
          version = Version.new(node.text)
          url = "#{ROOT}/#{version}/jruby-dist-#{version}-bin.tar.gz"
          Release.new(version: version, assets: {"tar.gz" => Asset.new(url: url)}, url: "#{ROOT}/#{version}/")
        end
        raise Error, "Empty JRuby release index" if releases.empty?

        releases
      rescue REXML::ParseException => e
        raise Error, "Invalid JRuby metadata: #{e.message}"
      end

      def resolve(release, required)
        release.assets.each_value do |asset|
          asset.sha256 = @http.get("#{asset.url}.sha256")
          asset.provenance = "upstream checksum"
        end
        super
      end
    end

    class TruffleRuby < Source
      API = "https://api.github.com/repos/truffleruby/truffleruby/releases"
      ROOT = "https://github.com/truffleruby/truffleruby/releases"

      def releases
        releases = []
        (1..100).each do |page|
          records = JSON.parse(@http.get("#{API}?per_page=100&page=#{page}"))
          raise Error, "Unexpected TruffleRuby releases response" unless records.is_a?(Array)

          releases.concat(parse(records))
          return releases if records.size < 100 && !releases.empty?
          raise Error, "Empty TruffleRuby release index" if records.empty? && releases.empty?
        end
        raise Error, "TruffleRuby release pagination did not finish"
      rescue JSON::ParserError => e
        raise Error, "Invalid TruffleRuby releases: #{e.message}"
      end

      def parse(records)
        records.filter_map do |record|
          tag = record.fetch("tag_name")
          raise Error, "Invalid TruffleRuby release tag" unless tag.is_a?(String)
          next if record.fetch("draft") || !tag.match?(/\Agraal-\d+\.\d+\.\d/)

          version = Version.new(tag.delete_prefix("graal-"))
          assets = record.fetch("assets").each_with_object({}) do |asset, result|
            name = asset.fetch("name")
            match = /\Atruffleruby-community-#{Regexp.escape(version.to_s)}-linux-(amd64|aarch64)\.tar\.gz\z/.match(name)
            next unless match

            result[match[1]] = Asset.new(
              url: "#{ROOT}/download/#{tag}/#{name}",
              sha256: asset["digest"]&.delete_prefix("sha256:"),
              provenance: "upstream asset digest"
            )
          end
          Release.new(version: version, assets: assets, url: "#{ROOT}/tag/#{tag}")
        end
      rescue KeyError, TypeError, NoMethodError => e
        raise Error, "Invalid TruffleRuby release: #{e.message}"
      end

      def resolve(release, required)
        required.each do |key|
          asset = release.assets.fetch(key) { raise Error, "Missing #{key} archive for #{release.version}" }
          next if asset.sha256

          asset.sha256 = @http.sha256(asset.url)
          asset.provenance = "computed from archive"
        end
        super
      end
    end
  end
end
