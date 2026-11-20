# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../refresh"

module ImagesMirror
  class MemoryRegistry < Registry
    attr_reader :objects, :reads, :copies
    attr_accessor :fail_copy, :corrupt_copy

    def initialize
      @objects = {}
      @reads = []
      @copies = []
    end

    def raw(ref, config: false)
      reads << [ref, config]
      objects.fetch([ref, config])
    end

    def copy(source, destination)
      copies << [source, destination]
      raise Error, "Copy failed" if fail_copy

      from = Reference.repository(source)
      to = Reference.repository(destination)
      objects.to_a.each do |(ref, config), value|
        next unless ref.start_with?("#{from}@")

        objects[[ref.sub(from, to), config]] = corrupt_copy ? "{}" : value
      end
    end

    def image(repository, arch, variant = nil)
      config = JSON.generate({"os" => "linux", "architecture" => arch})
      manifest = JSON.generate({"schemaVersion" => 2, "mediaType" => IMAGE_TYPES.first,
                                "config" => {"digest" => digest(config)}, "layers" => []})
      sha = digest(manifest)
      objects[["#{repository}@#{sha}", false]] = manifest
      objects[["#{repository}@#{sha}", true]] = config
      platform = {"os" => "linux", "architecture" => arch}
      platform["variant"] = variant if variant
      {"digest" => sha, "platform" => platform}
    end

    def index(ref, children)
      manifest = JSON.generate({"schemaVersion" => 2, "mediaType" => INDEX_TYPES.first, "manifests" => children})
      objects[[ref, false]] = manifest
      objects[["#{Reference.repository(ref)}@#{digest(manifest)}", false]] = manifest
      digest(manifest)
    end
  end

  class MirrorTest < Minitest::Test
    def setup
      @dir = Dir.mktmpdir("images-mirror")
      @path = File.join(@dir, "mirror.lock.yml")
      @source = "docker.io/library/alpine:3.23"
      @repository = Reference.repository(@source)
      @mirror = "ghcr.io/datadog/images-rb/mirror/#{@repository}"
      @entry = {"source" => @source, "mirror" => @mirror, "platforms" => %w[linux/amd64 linux/arm64]}
      @registry = MemoryRegistry.new
      @children = [@registry.image(@repository, "amd64"), @registry.image(@repository, "arm64", "v8"), @registry.image(@repository, "386")]
      @sha = @registry.index(@source, @children)
      @inventory_path = File.join(@dir, "mirror.yml")
      write_inventory
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def write_inventory
      File.write(@inventory_path, YAML.dump({"version" => 1, "images" => {"alpine:3.23" => @entry}}))
      @inventory = Inventory.new(@inventory_path)
    end

    def refresh(check: false)
      Refresh.new(@inventory, registry: @registry, output: StringIO.new).run(@path, check: check)
    end

    def test_inventory_covers_current_checkout
      root = File.expand_path("../../..", __dir__)
      Inventory.new(File.join(root, "mirror.yml")).check(root)
    end

    def test_canonicalisation_expands_docker_hub_defaults
      assert_equal "docker.io/library/alpine:3.23", Reference.canonical("alpine:3.23")
      assert_equal "docker.io/library/alpine:3.23", Reference.canonical("docker.io/alpine:3.23")
      assert_equal "docker.io/datadog/agent:latest", Reference.canonical("datadog/agent")
    end

    def test_inventory_rejects_registry_substitution
      assert_equal "public.ecr.aws/docker/library/alpine:3.23", Reference.canonical("public.ecr.aws/docker/library/alpine:3.23")
      @entry["source"] = "public.ecr.aws/docker/library/alpine:3.23"

      assert_raises(Error) { write_inventory }
    end

    def test_inventory_rejects_tag_changes
      @entry["source"] = "docker.io/library/alpine:latest"
      assert_raises(Error) { write_inventory }
    end

    def test_inventory_fails_for_unmapped_from_and_copy
      FileUtils.mkdir_p(File.join(@dir, "src"))
      path = File.join(@dir, "src/Dockerfile")
      File.write(path, "FROM alpine:3.23 AS base\nFROM base\nCOPY --from=redis:8 /bin/redis /bin/redis\nCOPY --from=0 /a /b\n")

      assert_equal ["alpine:3.23", "redis:8"], Inputs.external(path)
      assert_raises(Error) { @inventory.check(@dir) }
    end

    def test_runtime_dependencies_are_not_mirrored
      path = File.join(@dir, "Dockerfile")
      File.write(path, "FROM ghcr.io/datadog/images-rb/engines/ruby:4.0-gnu\n")

      assert_empty Inputs.external(path)
    end

    def test_refresh_copies_resolved_digest_without_resolving_tag_again
      refresh

      assert_equal 1, @registry.reads.count { |ref, _| ref == @source }
      assert_equal [["#{@repository}@#{@sha}", "#{@mirror}:#{@sha.tr(":", "-")}"]], @registry.copies
    end

    def test_lock_records_immutable_inputs_and_extra_platforms
      refresh
      lock = YAML.safe_load_file(@path).fetch("images").fetch("alpine:3.23")

      assert_equal "#{@repository}@#{@sha}", lock.fetch("upstream")
      assert_equal "#{@mirror}@#{@sha}", lock.fetch("mirror")
      assert_equal %w[linux/386 linux/amd64 linux/arm64], lock.fetch("manifests").map { |entry| entry.fetch("platform") }
    end

    def test_unchanged_refresh_does_not_rewrite_lock
      refresh
      File.utime(Time.at(1), Time.at(1), @path)
      before = File.read(@path)
      refresh

      assert_equal before, File.read(@path)
      assert_equal Time.at(1), File.mtime(@path)
    end

    def test_inspection_neither_copies_nor_writes
      refresh(check: true)

      assert_empty @registry.copies
      refute_path_exists @path
    end

    def test_missing_required_platform_fails_before_copy
      @registry.index(@source, @children.take(1))
      assert_raises(Error) { refresh }
      assert_empty @registry.copies
      refute_path_exists @path
    end

    def test_failed_copy_preserves_existing_lock
      File.write(@path, "adopted lock\n")
      @registry.fail_copy = true
      assert_raises(Error) { refresh }
      assert_equal "adopted lock\n", File.read(@path)
    end

    def test_later_failure_cannot_adopt_partial_refresh
      File.write(@path, "adopted lock\n")
      @inventory.images["alpine:missing-platform"] = @entry.merge("source" => "#{@repository}:missing-platform")
      @registry.index("#{@repository}:missing-platform", @children.take(1))

      assert_raises(Error) { refresh }
      assert_equal 1, @registry.copies.size
      assert_equal "adopted lock\n", File.read(@path)
    end

    def test_mirror_digest_mismatch_preserves_existing_lock
      File.write(@path, "adopted lock\n")
      @registry.corrupt_copy = true
      assert_raises(Error) { refresh }
      assert_equal "adopted lock\n", File.read(@path)
    end

    def test_child_digest_mismatch_fails
      @registry.objects[["#{@repository}@#{@children.first.fetch("digest")}", false]] = "{}"
      assert_raises(Error) { refresh }
      refute_path_exists @path
    end

    def test_config_digest_mismatch_fails
      @registry.objects[["#{@repository}@#{@children.first.fetch("digest")}", true]] = "{}"
      assert_raises(Error) { refresh }
      refute_path_exists @path
    end

    def test_platform_descriptor_must_match_config
      @children.first["platform"]["architecture"] = "arm64"
      @registry.index(@source, @children)
      assert_raises(Error) { refresh }
      refute_path_exists @path
    end

    def test_single_platform_manifest_is_checked
      @registry.objects[[@source, false]] = @registry.objects.fetch(["#{@repository}@#{@children.first.fetch("digest")}", false])
      @entry["platforms"] = ["linux/amd64"]
      write_inventory
      refresh

      assert_equal 1, YAML.safe_load_file(@path).fetch("images").fetch("alpine:3.23").fetch("manifests").size
    end

    def test_nested_index_keeps_all_platforms
      nested = @registry.index("#{@repository}:nested", @children)
      @registry.index(@source, [{"digest" => nested}])
      refresh

      assert_equal 3, YAML.safe_load_file(@path).fetch("images").fetch("alpine:3.23").fetch("manifests").size
    end

    def test_variant_cannot_satisfy_a_different_architecture_requirement
      @children[1]["platform"]["variant"] = "v9"
      @registry.index(@source, @children)

      assert_raises(Error) { refresh }
      assert_empty @registry.copies
    end
  end
end
