#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require_relative "engine_updates/upstream"
require_relative "engine_updates/repository"
require_relative "engine_updates/plan"

module EngineUpdates
  class CLI
    def self.run(arguments, root: File.expand_path("..", __dir__), out: $stdout, err: $stderr, http: HTTP.new)
      options = {format: "text", dry_run: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby script/update-engines.rb [options]"
        opts.on("--engine NAME", Plan::POLICY.keys, "Update only this engine") { |value| options[:engine] = value }
        opts.on("--dry-run", "Describe changes without writing files") { options[:dry_run] = true }
        opts.on("--format FORMAT", %w[text json], "Output format (default: text)") { |value| options[:format] = value }
        opts.on("-h", "--help", "Show this help") do
          out.puts(opts)
          return 0
        end
      end
      parser.parse!(arguments)
      raise Error, "Unexpected arguments: #{arguments.join(" ")}" unless arguments.empty?

      repository = Repository.new(root)
      changes = []
      notes = []
      engines = options[:engine] ? [options[:engine]] : Plan::POLICY.keys
      engines.each do |engine|
        installed = repository.inventory(engine)
        if installed.empty?
          raise Error, "No seed series for #{engine}" if options[:engine]

          notes << "#{engine}: no seed series; skipped"
          next
        end
        source = Upstream.for(engine, http: http)
        plan = Plan.new(engine, installed, source.releases)
        plan.changes.each { |change| repository.prepare(change, source) }
        changes.concat(plan.changes)
        notes.concat(plan.notes)
      end
      repository.validate
      repository.apply unless options[:dry_run]
      if options[:format] == "json"
        out.puts JSON.pretty_generate(changes: changes.map(&:to_h), notes: notes, files: repository.edits.keys.sort)
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
      0
    rescue Error, OptionParser::ParseError => e
      err.puts "Engine update failed: #{e.message}"
      1
    end
  end
end

exit EngineUpdates::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
