# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "stringio"
require_relative "../update-engines"

class EngineUpdatesTest < Minitest::Test
  include EngineUpdates

  class HTTPFixture
    attr_reader :requests

    def initialize(responses = {})
      @responses = responses
      @requests = []
    end

    def get(url)
      @requests << url
      @responses.fetch(url) { raise EngineUpdates::Error, "Unexpected request: #{url}" }
    end

    def sha256(url)
      Digest::SHA256.hexdigest(get(url))
    end
  end

  Connection = Struct.new(:responses, :requests, :max_retries) do
    def request(request)
      requests << request
      yield responses.shift
    end
  end

  def setup
    @root = Dir.mktmpdir("engine-updates-")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_numeric_versions_patchlevels_and_prereleases
    ordered = %w[1.8.7-p17 1.8.7-p374 1.8.7-p376 1.9.0-5 1.9.3-p551 2.0.0-p648 3.4.9 3.4.10 4.1.0-preview2 4.1.0-preview10 4.1.0-rc1 4.1.0 9.4.12.0 9.4.12.1 10.0.0.0.pre1 10.0.0.0.rc1 10.0.0.0]
    assert_equal ordered, ordered.reverse.map { |text| Version.new(text) }.sort.map(&:to_s)
    assert_raises(Error) { Version.new("4.1.0-nightly") }
    assert_operator Version.new("1.8.5-p11-repack"), :>, Version.new("1.8.5-p11")
  end

  def test_plan_updates_older_series_and_catches_up_new_series
    installed = [installed("3.4.7"), installed("4.0.1")]
    releases = %w[1.6.8 3.3.9 3.4.8 4.0.0 4.1.0-preview1 4.1.0-rc1 5.0.0].map { |text| release(text) }
    plan = Plan.new("ruby", installed, releases)
    assert_equal %w[update minor major], plan.changes.map(&:kind)
    assert_equal %w[3.4.8 4.1.0-rc1 5.0.0], plan.changes.map { |change| change.release.version.to_s }
    assert_equal %w[3.4 4.0 4.1], plan.changes.map(&:template)
  end

  def test_policy_exclusions_missing_seed_and_pinned_sources
    series = installed("1.8.7-p376")
    series.pinned = true
    plan = Plan.new("ruby", [series], [release("1.8.7-p999"), release("1.9.3-p551")], policy: {minimum: "1.8", exclude: ["1.9.3-p551"]})
    assert_empty plan.changes
    assert_match(/manually pinned/, plan.notes.first)
    assert_empty Plan.new("ruby", [installed("1.6.7")], [release("1.6.8")]).changes
    assert_raises(Error) { Plan.new("ruby", [], []) }
  end

  def test_ruby_index_groups_formats_and_rejects_bad_metadata
    source = Upstream::CRuby.new(HTTPFixture.new)
    releases = source.parse(fixture("ruby-index.txt"))
    assert_equal 6, releases.size
    chosen = releases.find { |item| item.version.to_s == "3.4.8" }
    source.resolve(chosen, ["tar.xz"])
    assert_equal "3" * 64, chosen.assets.fetch("tar.xz").sha256
    assert_raises(Error) { source.resolve(chosen, ["tar.bz2"]) }
    assert_raises(Error) { source.parse("<html>unavailable</html>") }
    assert_raises(Error) { source.checksum("invalid") }
    assert_raises(Error) { source.checksum(nil) }
  end

  def test_http_redirects_do_not_forward_github_credentials_and_responses_are_cached
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["location"] = "https://example.com/archive"
    success = response("archive bytes")
    connection = Connection.new([redirect, success], [])
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(connection) }) do
      http = HTTP.new(token: "test-token")
      2.times { assert_equal "archive bytes", http.get("https://api.github.com/example") }
    end
    assert_equal 2, connection.requests.size
    assert_equal "Bearer test-token", connection.requests.first["Authorization"]
    assert_nil connection.requests.last["Authorization"]
    assert_equal 0, connection.max_retries
    assert_raises(Error) { HTTP.new.get("http://example.com/archive") }
  end

  def test_http_retries_transient_statuses_but_not_partially_streamed_archives
    connection = Connection.new([Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable"), response("archive")], [])
    http = HTTP.new
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(connection) }) do
      http.stub(:sleep, nil) { assert_equal "archive", http.get("https://example.com/archive") }
    end
    assert_equal 2, connection.requests.size

    partial = response("partial")
    partial.define_singleton_method(:read_body) do |&block|
      block.call("partial")
      raise IOError, "connection interrupted"
    end
    connection = Connection.new([partial], [])
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(connection) }) do
      assert_raises(Error) { HTTP.new.sha256("https://example.com/archive") }
    end
    assert_equal 1, connection.requests.size
  end

  def test_jruby_discovers_all_series_and_resolves_only_selected_checksums
    url = "#{Upstream::JRuby::ROOT}/10.0.3.0/jruby-dist-10.0.3.0-bin.tar.gz.sha256"
    http = HTTPFixture.new(url => "a" * 64 + "\n")
    source = Upstream::JRuby.new(http)
    releases = source.parse(fixture("jruby-metadata.xml"))
    assert_equal 5, releases.size
    assert_empty http.requests
    source.resolve(releases[2], ["tar.gz"])
    assert_equal [url], http.requests
    assert_equal "a" * 64, releases[2].assets.fetch("tar.gz").sha256
    assert_raises(Error) { source.parse("<metadata>") }
  end

  def test_truffleruby_paginates_and_selects_community_native_assets
    records = JSON.parse(fixture("truffleruby-releases.json"))
    first = Array.new(100) { {"tag_name" => "nightly", "draft" => false} }
    http = HTTPFixture.new(
      "#{Upstream::TruffleRuby::API}?per_page=100&page=1" => JSON.generate(first),
      "#{Upstream::TruffleRuby::API}?per_page=100&page=2" => JSON.generate(records)
    )
    releases = Upstream::TruffleRuby.new(http).releases
    assert_equal %w[40.0.1 41.0.0-rc1], releases.map { |item| item.version.to_s }
    assert_equal %w[aarch64 amd64], releases.first.assets.keys.sort
    assert_equal "a" * 64, releases.first.assets.fetch("amd64").sha256
    assert_equal 2, http.requests.size
  end

  def test_truffleruby_computes_missing_digests_and_requires_both_archives
    source = Upstream::TruffleRuby.new(HTTPFixture.new)
    chosen = source.parse(JSON.parse(fixture("truffleruby-releases.json")))[1]
    responses = chosen.assets.values.to_h { |asset| [asset.url, "archive bytes"] }
    source = Upstream::TruffleRuby.new(HTTPFixture.new(responses))
    source.resolve(chosen, %w[amd64 aarch64])
    assert_equal Digest::SHA256.hexdigest("archive bytes"), chosen.assets.fetch("amd64").sha256
    assert_equal "computed from archive", chosen.assets.fetch("amd64").provenance
    chosen.assets.delete("aarch64")
    assert_raises(Error) { source.resolve(chosen, %w[amd64 aarch64]) }
  end

  def test_patch_edits_all_runtime_variants_without_touching_dependencies
    seed("ruby", "3.4.7", %w[gnu musl centos])
    repository = prepare("ruby", [release("3.4.8")])
    assert_equal 3, repository.edits.size
    repository.apply
    %w[gnu musl centos].each do |variant|
      text = read("src/engines/ruby/3.4/Dockerfile.#{variant}")
      assert_includes text, 'RUBY_VERSION="3.4.8"'
      assert_includes text, "gem install bundler --version 3.4.7"
      assert_includes text, "a" * 64
    end
    assert_empty prepare("ruby", [release("3.4.8")]).edits
  end

  def test_new_series_copy_files_gemfiles_and_matrix_entries
    seed("ruby", "3.4.7", %w[gnu musl])
    write("src/engines/ruby/3.4/setup", "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, File.join(@root, "src/engines/ruby/3.4/setup"))
    repository = prepare("ruby", [release("3.5.0-preview1"), release("4.0.0")])
    repository.apply
    %w[3.5 4.0].each do |name|
      assert_includes read("src/engines/ruby/#{name}/Dockerfile.gnu"), "RUBY_MAJOR=\"#{name}\""
      assert_includes read("src/engines/ruby/#{name}/Dockerfile.gnu.gcc"), "ruby:#{name}-gnu"
      assert_equal read("gemfiles/ruby-3.4.gemfile"), read("gemfiles/ruby-#{name}.gemfile")
      assert_equal 0o755, File.stat(File.join(@root, "src/engines/ruby/#{name}/setup")).mode & 0o777
      Repository::MATRICES.each do |path|
        assert_equal 2, read(path).scan("version: \"#{name}\"").size
        assert_includes read(path), "# Preserve this comment"
      end
    end
    assert_empty prepare("ruby", [release("3.5.0-preview1"), release("4.0.0")]).edits
  end

  def test_jruby_preserves_gnu_compiler_alias_and_rewrites_stage_names
    seed("jruby", "10.0.2.0", %w[gnu musl])
    prepare("jruby", [release("10.1.2.0", format: "tar.gz")]).apply
    assert_includes read("src/engines/jruby/10.1/Dockerfile.gnu"), "AS jruby-10.1.2.0-jre22"
    assert_includes read("src/engines/jruby/10.1/Dockerfile.gnu"), "eclipse-temurin:22-jammy"
    assert_equal 1, read(Repository::MATRICES.last).scan('version: "10.1"').size
    refute File.exist?(File.join(@root, "src/engines/jruby/10.1/Dockerfile.gnu.gcc"))
  end

  def test_jruby_prerelease_stage_names_advance_to_final
    seed("jruby", "10.0.2.0", %w[gnu musl])
    prepare("jruby", [release("10.1.0.0.RC1", format: "tar.gz")]).apply
    assert_includes read("src/engines/jruby/10.1/Dockerfile.gnu"), "AS jruby-10.1.0.0.rc1-jre22"
    prepare("jruby", [release("10.1.0.0", format: "tar.gz")]).apply
    assert_includes read("src/engines/jruby/10.1/Dockerfile.gnu"), "AS jruby-10.1.0.0-jre22"
  end

  def test_truffleruby_edits_checksums_by_architecture
    seed("truffleruby", "40.0.0", ["gnu"])
    source = Upstream::TruffleRuby.new(HTTPFixture.new)
    release = source.parse(JSON.parse(fixture("truffleruby-releases.json")))[0]
    prepare("truffleruby", [release]).apply
    text = read("src/engines/truffleruby/40.0/Dockerfile.gnu")
    assert_match(/arch=amd64\n\s+sha256=#{"a" * 64}/, text)
    assert_match(/arch=aarch64\n\s+sha256=#{"b" * 64}/, text)
    assert_includes text, "TRUFFLERUBY_VERSION=40.0.1"
  end

  def test_conflicting_versions_and_missing_matrix_entries_are_errors
    seed("ruby", "3.4.7", %w[gnu musl])
    path = "src/engines/ruby/3.4/Dockerfile.musl"
    write(path, read(path).sub('RUBY_VERSION="3.4.7"', 'RUBY_VERSION="3.4.6"'))
    assert_raises(Error) { Repository.new(@root).inventory("ruby") }
    write(path, read(path).sub('RUBY_VERSION="3.4.6"', 'RUBY_VERSION="3.4.7"'))
    write(Repository::MATRICES.first, read(Repository::MATRICES.first).sub('version: "3.4"', 'version: "3.3"'))
    assert_raises(Error) { prepare("ruby", [release("4.0.0")]) }
  end

  def test_preflight_failure_and_concurrent_edits_leave_files_untouched
    seed("ruby", "3.4.7", ["gnu"])
    before = snapshot
    bad = release("4.0.0")
    bad.assets.clear
    assert_raises(Error) { prepare("ruby", [release("3.4.8"), bad]) }
    assert_equal before, snapshot

    repository = prepare("ruby", [release("3.4.8")])
    path = "src/engines/ruby/3.4/Dockerfile.gnu"
    write(path, read(path) + "# Local edit\n")
    assert_raises(Error) { repository.apply }
    assert_includes read(path), 'RUBY_VERSION="3.4.7"'
    assert_includes read(path), "# Local edit"
  end

  def test_cli_dry_run_and_apply_share_the_same_plan
    seed("ruby", "3.4.7", ["gnu"])
    responses = {Upstream::CRuby::INDEX => fixture("ruby-index.txt")}
    before = snapshot
    out = StringIO.new
    status = CLI.run(%w[--dry-run --format json], root: @root, out: out, http: HTTPFixture.new(responses))
    assert_equal 0, status
    assert_equal before, snapshot
    result = JSON.parse(out.string)
    assert_equal %w[3.4.8 4.1.0-rc1], result.fetch("changes").map { |change| change.fetch("to") }
    assert_includes result.fetch("notes"), "truffleruby: no seed series; skipped"

    out = StringIO.new
    assert_equal 0, CLI.run(%w[--format json], root: @root, out: out, http: HTTPFixture.new(responses))
    assert_equal result, JSON.parse(out.string)
    refute_equal before, snapshot
  end

  def test_cli_reports_network_failure_and_explicit_missing_engine
    seed("ruby", "3.4.7", ["gnu"])
    before = snapshot
    err = StringIO.new
    assert_equal 1, CLI.run([], root: @root, err: err, http: HTTPFixture.new)
    assert_match(/Unexpected request/, err.string)
    assert_equal before, snapshot
    assert_equal 1, CLI.run(%w[--engine truffleruby], root: @root, err: StringIO.new, http: HTTPFixture.new)
  end

  private

  def response(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:read_body) { |&block| block.call(body) }
    response
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", name))
  end

  def installed(text)
    version = Version.new(text)
    Series.new(engine: "ruby", name: version.series, version: version, files: {}, pinned: false)
  end

  def release(text, format: "tar.xz")
    Release.new(version: Version.new(text), assets: {format => Asset.new(url: "https://example.com/#{text}.#{format}", sha256: "a" * 64, provenance: "fixture")}, url: "https://example.com/releases")
  end

  def seed(engine, version, variants)
    name = Version.new(version).series
    runtime = fixture("#{engine}.Dockerfile")
    variants.each do |variant|
      write("src/engines/#{engine}/#{name}/Dockerfile.#{variant}", runtime)
      next if engine == "jruby" && variant == "gnu"

      %w[gcc clang].each do |compiler|
        write("src/engines/#{engine}/#{name}/Dockerfile.#{variant}.#{compiler}", "FROM ghcr.io/datadog/images-rb/engines/#{engine}:#{name}-#{variant}\n")
      end
    end
    write("gemfiles/#{engine}-#{name}.gemfile", "source \"https://rubygems.org\"\ngem \"rake\"\n")
    Repository::MATRICES.each do |path|
      entries = variants.reject { |variant| path == Repository::MATRICES.last && engine == "jruby" && variant == "gnu" }.map do |variant|
        "          - engine: #{engine}\n            version: \"#{name}\"\n            libc: #{variant}\n            arch: [\"x86_64\", \"aarch64\"]\n"
      end.join
      write(path, "on:\n  workflow_call:\njobs:\n  build:\n    strategy:\n      matrix:\n        include:\n          # Preserve this comment\n#{entries}")
    end
  end

  def prepare(engine, releases)
    repository = Repository.new(@root)
    plan = Plan.new(engine, repository.inventory(engine), releases)
    source = Upstream::Source.new(HTTPFixture.new)
    plan.changes.each { |change| repository.prepare(change, source) }
    repository.validate
    repository
  end

  def write(path, text)
    absolute = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, text)
  end

  def read(path)
    File.read(File.join(@root, path))
  end

  def snapshot
    Dir.glob("#{@root}/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
  end
end
