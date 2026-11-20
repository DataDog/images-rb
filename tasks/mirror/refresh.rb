# frozen_string_literal: true

require "tempfile"
require_relative "registry"

module ImagesMirror
  class Refresh
    def initialize(inventory, registry: Registry.new, output: $stdout)
      @inventory = inventory
      @registry = registry
      @output = output
    end

    def run(path, check: false)
      entries = @inventory.images.to_h do |ref, entry|
        @output.puts "Resolve #{entry.fetch("source")}"
        source = @registry.snapshot(entry.fetch("source"), entry.fetch("platforms"))
        sha = source.fetch("digest")
        upstream = "#{Reference.repository(entry.fetch("source"))}@#{sha}"
        mirror = "#{entry.fetch("mirror")}@#{sha}"
        unless check
          # Content-addressed retention tags never move on a later refresh.
          @registry.copy(upstream, "#{entry.fetch("mirror")}:#{sha.tr(":", "-")}")
          destination = @registry.snapshot(mirror, entry.fetch("platforms"))
          raise Error, "Mirror differs from upstream: #{ref}" unless source == destination
        end
        [ref, {"source" => entry.fetch("source"), "upstream" => upstream, "mirror" => mirror,
               "platforms" => entry.fetch("platforms"), "manifests" => source.fetch("manifests")}]
      end
      return if check

      contents = YAML.dump({"version" => 1, "images" => entries})
      return if File.exist?(path) && File.read(path) == contents

      # A failure anywhere above leaves the previously adopted lock intact.
      Tempfile.create([".mirror-lock", ".yml"], File.dirname(path)) do |file|
        file.write(contents)
        file.flush
        file.fsync
        File.rename(file.path, path)
      end
      @output.puts "Wrote #{path}; review and commit to adopt these inputs."
    end
  end
end
