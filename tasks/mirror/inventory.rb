# frozen_string_literal: true

require "yaml"

module ImagesMirror
  class Error < StandardError; end

  module Reference
    def self.canonical(ref)
      raise Error, "Unsupported image reference: #{ref}" unless ref.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._\/:@-]*\z/)

      parts = ref.split("/")
      parts.unshift("library") if parts.size == 1
      parts.unshift("docker.io") unless parts.first.match?(/[.:]/) || parts.first == "localhost"
      parts.insert(1, "library") if parts.size == 2 && parts.first == "docker.io"
      parts[-1] += ":latest" unless parts.last.match?(/[:@]/)
      parts.join("/")
    end

    def self.repository(ref)
      ref.sub(/@.*\z/, "").sub(/:[^\/]*\z/, "")
    end
  end

  module Inputs
    def self.external(path)
      stages = []
      refs = []
      File.read(path).gsub(/\\\r?\n/, " ").each_line do |line|
        if (match = line.match(/^\s*FROM\s+(?:--platform=\S+\s+)?(\S+)(?:\s+AS\s+(\S+))?\s*(?:#.*)?$/i))
          refs << match[1] unless stages.include?(match[1].downcase) || match[1] == "scratch"
          stages << match[2].downcase if match[2]
        elsif line.match?(/^\s*FROM\b/i)
          raise Error, "Unsupported FROM in #{path}: #{line.strip}"
        elsif line.match?(/^\s*COPY\b/i) && (match = line.match(/--from=(\S+)/))
          ref = match[1]
          refs << ref unless stages.include?(ref.downcase) || ref.match?(/\A\d+\z/)
        end
      end
      # These are outputs of this build graph, not upstream mirror inputs.
      refs.uniq.reject { |ref| ref.start_with?("ghcr.io/datadog/images-rb/engines/") }
    end
  end

  class Inventory
    attr_reader :images

    def initialize(path)
      data = YAML.safe_load_file(path)
      raise Error, "Unsupported inventory version" unless data.fetch("version") == 1

      @images = data.fetch("images")
      raise Error, "Empty inventory" unless images.is_a?(Hash) && !images.empty?

      images.each do |ref, entry|
        raise Error, "Source changes registry or tag for #{ref}" unless entry.fetch("source") == Reference.canonical(ref)
        expected = "ghcr.io/datadog/images-rb/mirror/#{Reference.repository(entry.fetch("source"))}"
        raise Error, "Unexpected mirror destination for #{ref}" unless entry.fetch("mirror") == expected
        platforms = entry.fetch("platforms")
        unless platforms.is_a?(Array) && !platforms.empty? && platforms.uniq == platforms && (platforms - %w[linux/amd64 linux/arm64]).empty?
          raise Error, "Invalid required platforms for #{ref}"
        end
      end
    end

    def check(root)
      refs = Dir.glob(File.join(root, "src/**/Dockerfile*")).flat_map { |path| Inputs.external(path) }.uniq
      missing = refs - images.keys
      unused = images.keys - refs
      raise Error, "Inventory mismatch; missing: #{missing.join(", ")}; unused: #{unused.join(", ")}" unless missing.empty? && unused.empty?
    end
  end
end
