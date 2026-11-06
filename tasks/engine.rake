# frozen_string_literal: true

# ruby-version-min: 2.3.0

# @type self: Rake::DSL

namespace :engine do
  desc <<~DESC
    Update engine releases (requires Ruby 3.3 or newer).

    Accepts an optional engine argument, e.g. 'engine:update[jruby]'.

    Considers these env vars:
    - DRY_RUN=1: describe changes without writing files (default: 0).
    - FORMAT=json: output format, text or json (default: text).
  DESC
  task :update, [:engine] do |_, args|
    fail "engine:update requires Ruby 3.3 or newer" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")
    fail ArgumentError, "Expected at most one engine argument" unless args.extras.empty?
    dry_run = ENV.fetch("DRY_RUN", "0")
    fail ArgumentError, "DRY_RUN must be 0 or 1" unless %w[0 1].include?(dry_run)

    # Image tests load these tasks on historical Rubies; load host code only on invocation.
    require_relative "engine/update"
    EngineUpdates.update(engine: args[:engine], dry_run: dry_run == "1", format: ENV.fetch("FORMAT", "text"))
  end

  desc "Test the engine updater (requires Ruby 3.3 or newer)"
  task :test do
    fail "engine:test requires Ruby 3.3 or newer" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")

    ruby File.expand_path("engine/test/engine_updates_test.rb", __dir__)
  end
end
