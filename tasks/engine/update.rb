# frozen_string_literal: true

require "json"
require_relative "upstream"
require_relative "repository"
require_relative "plan"

module EngineUpdates
  def self.update(engine: nil, dry_run: false, format: "text", root: File.expand_path("../..", __dir__), out: $stdout, http: HTTP.new)
    raise Error, "Unknown engine: #{engine}" if engine && !Plan::POLICY.key?(engine)
    raise Error, "Unknown output format: #{format}" unless %w[text json].include?(format)

    repository = Repository.new(root)
    changes = []
    notes = []
    engines = engine ? [engine] : Plan::POLICY.keys
    engines.each do |name|
      installed = repository.inventory(name)
      if installed.empty?
        raise Error, "No seed series for #{name}" if engine

        notes << "#{name}: no seed series; skipped"
        next
      end
      source = Upstream.for(name, http: http)
      plan = Plan.new(name, installed, source.releases)
      plan.changes.each { |change| repository.prepare(change, source) }
      changes.concat(plan.changes)
      notes.concat(plan.notes)
    end
    repository.validate
    repository.apply unless dry_run
    report = {changes: changes.map(&:to_h), notes: notes, files: repository.edits.keys.sort}
    if format == "json"
      out.puts JSON.pretty_generate(report)
    else
      out.puts(changes.empty? ? "No engine updates available." : "Engine updates:")
      changes.each do |change|
        origin = change.previous ? "#{change.previous} to " : ""
        template = (change.kind == "update") ? "" : " (#{change.kind} series copied from #{change.template}; best effort)"
        out.puts "- #{change.engine}: #{origin}#{change.release.version}#{template}"
        out.puts "  Source: #{change.release.url}"
        change.release.assets.each do |name, asset|
          out.puts "  #{name}: #{asset.url} (SHA-256 #{asset.sha256}; #{asset.provenance})"
        end
      end
      notes.each { |note| out.puts "- #{note}" }
    end
    report
  end
end
