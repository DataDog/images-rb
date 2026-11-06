# frozen_string_literal: true

require_relative "version"

module EngineUpdates
  class Plan
    POLICY = {
      "ruby" => {minimum: "1.8", exclude: []},
      "jruby" => {minimum: "9.2", exclude: []},
      "truffleruby" => {minimum: "40.0", exclude: []}
    }.freeze

    attr_reader :changes, :notes

    def initialize(engine, installed, releases, policy: POLICY.fetch(engine))
      @changes = []
      @notes = []
      raise Error, "No seed series for #{engine}" if installed.empty?

      current = installed.to_h { |series| [series.name, series] }
      newest = current.keys.max_by { |name| series_key(name) }
      candidates = releases.reject do |release|
        (series_key(release.version.series) <=> series_key(policy.fetch(:minimum))) < 0
      end
      candidates.reject! { |release| policy.fetch(:exclude).include?(release.version.to_s) }
      latest = candidates.group_by { |release| release.version.series }.transform_values { |list| list.max_by(&:version) }

      installed.each do |series|
        if series.pinned
          @notes << "#{engine} #{series.name}: manually pinned source (#{series.version})"
          next
        end
        release = latest[series.name]
        next unless release && release.version > series.version

        @changes << Change.new(engine: engine, kind: "update", previous: series.version, release: release, template: series.name)
      end

      latest.keys.sort_by { |name| series_key(name) }.each do |name|
        next if current.key?(name) || (series_key(name) <=> series_key(newest)) <= 0

        template = newest
        kind = (name.split(".").first == template.split(".").first) ? "minor" : "major"
        @changes << Change.new(engine: engine, kind: kind, release: latest.fetch(name), template: template)
        newest = name
      end
    end

    private

    def series_key(name)
      name.split(".").map(&:to_i)
    end
  end
end
