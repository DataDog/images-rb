# frozen_string_literal: true

module EngineUpdates
  class Error < StandardError; end

  class Version
    include Comparable

    PATTERN = /\A(\d+\.\d+\.\d+(?:\.\d+)?)(?:[-.](alpha|beta|preview|pre|rc)(\d+)|-p?(\d+))?(-repack)?\z/i
    STAGES = {"alpha" => 0, "beta" => 1, "preview" => 2, "pre" => 2, "rc" => 3, nil => 4}.freeze

    attr_reader :text, :series

    def initialize(text)
      match = text.is_a?(String) && PATTERN.match(text)
      raise Error, "Unrecognised release version: #{text}" unless match

      @text = text
      numbers = match[1].split(".").map(&:to_i)
      @series = numbers.take(2).join(".")
      numbers << 0 while numbers.size < 4
      numbers[3] = match[4].to_i if match[4]
      @key = [numbers, STAGES.fetch(match[2]&.downcase), match[3].to_i, match[5] ? 1 : 0]
    end

    def <=>(other)
      key <=> other.key
    end

    def to_s
      text
    end

    protected

    attr_reader :key
  end

  Asset = Struct.new(:url, :sha256, :provenance, keyword_init: true)
  Release = Struct.new(:version, :assets, :url, keyword_init: true)
  Series = Struct.new(:engine, :name, :version, :files, :pinned, keyword_init: true)
  Change = Struct.new(:engine, :kind, :previous, :release, :template, keyword_init: true) do
    def to_h
      {
        engine: engine, kind: kind, series: release.version.series,
        from: previous&.to_s, to: release.version.to_s, template: template,
        source: release.url,
        assets: release.assets.transform_values(&:to_h)
      }
    end
  end
end
