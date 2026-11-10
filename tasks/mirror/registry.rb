# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require_relative "inventory"

module ImagesMirror
  class Registry
    INDEX_TYPES = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json].freeze
    IMAGE_TYPES = %w[application/vnd.oci.image.manifest.v1+json application/vnd.docker.distribution.manifest.v2+json].freeze

    def run(*args)
      timeout = (args.first == "copy") ? "15m" : "2m"
      out, err, status = Open3.capture3("skopeo", "--command-timeout", timeout, *args)
      raise Error, "skopeo #{args.first} failed: #{err.strip}" unless status.success?

      out
    end

    def raw(ref, config: false)
      args = ["inspect", "--retry-times", "3", "--raw"]
      args << "--config" if config
      run(*args, "docker://#{ref}")
    end

    def copy(source, destination)
      run("copy", "--retry-times", "3", "--all", "--preserve-digests", "docker://#{source}", "docker://#{destination}")
    end

    def digest(raw)
      "sha256:#{Digest::SHA256.hexdigest(raw)}"
    end

    def verify(raw, expected)
      raise Error, "Digest mismatch: expected #{expected}, got #{digest(raw)}" unless digest(raw) == expected
    end

    def snapshot(ref, required)
      root = raw(ref)
      sha = digest(root)
      verify(root, ref.split("@", 2).last) if ref.include?("@")
      manifests = manifests(Reference.repository(ref), root, sha)
      available = manifests.map { |entry| entry.fetch("platform") }
      missing = required - available
      raise Error, "#{ref}: missing #{missing.join(", ")}; available: #{available.uniq.join(", ")}" unless missing.empty?

      {"digest" => sha, "manifests" => manifests.sort_by { |entry| [entry.fetch("platform"), entry.fetch("digest")] }}
    end

    def manifests(repository, raw, sha, platform = nil)
      data = JSON.parse(raw)
      raise Error, "Unsupported manifest schema at #{repository}@#{sha}" unless data.fetch("schemaVersion") == 2

      if INDEX_TYPES.include?(data.fetch("mediaType"))
        data.fetch("manifests").flat_map do |entry|
          child = self.raw("#{repository}@#{entry.fetch("digest")}")
          verify(child, entry.fetch("digest"))
          manifests(repository, child, entry.fetch("digest"), entry["platform"])
        end
      elsif IMAGE_TYPES.include?(data.fetch("mediaType"))
        config = self.raw("#{repository}@#{sha}", config: true)
        verify(config, data.fetch("config").fetch("digest"))
        config = JSON.parse(config)
        if platform
          %w[os architecture variant].each do |key|
            if platform[key] && config[key] && platform[key] != config[key]
              raise Error, "Platform/config mismatch at #{repository}@#{sha}: #{key}"
            end
          end
        end
        os = config.fetch("os")
        arch = config.fetch("architecture")
        variant = (platform || {})["variant"] || config["variant"]
        variant = nil if arch == "arm64" && variant == "v8"
        [{"digest" => sha, "platform" => [os, arch, variant].compact.join("/")}]
      else
        raise Error, "Unsupported manifest type at #{repository}@#{sha}: #{data["mediaType"]}"
      end
    end
  end
end
