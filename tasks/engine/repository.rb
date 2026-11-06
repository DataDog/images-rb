# frozen_string_literal: true

require "fileutils"
require "tempfile"
require "yaml"
require_relative "version"

module EngineUpdates
  class Repository
    MATRICES = %w[.github/workflows/build-ruby.yml .github/workflows/build-ruby-compilers.yml].freeze
    VARIABLES = {
      "ruby" => ["RUBY_VERSION", "RUBY_DOWNLOAD_SHA256"],
      "jruby" => ["JRUBY_VERSION", "JRUBY_SHA256"],
      "truffleruby" => ["TRUFFLERUBY_VERSION", nil]
    }.freeze
    ARCHES = {"x86_64" => "amd64", "aarch64" => "aarch64"}.freeze
    TRUFFLE_HASH = /^([ \t]*(x86_64|aarch64)\)\n[ \t]*arch=(amd64|aarch64)\n[ \t]*sha256=)([a-f0-9]{64})(?=\n)/

    attr_reader :edits

    def initialize(root)
      @root = File.expand_path(root)
      @originals = {}
      @edits = {}
      @modes = {}
      @series = {}
    end

    def inventory(engine)
      Dir.glob(File.join(@root, "src/engines", engine, "*")).sort.filter_map do |directory|
        next unless File.directory?(directory)

        name = File.basename(directory)
        raise Error, "Invalid series directory: #{directory}" unless /\A\d+\.\d+\z/.match?(name)

        files = Dir.glob("#{directory}/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
          relative = path.delete_prefix("#{@root}/")
          [relative, read(relative)]
        end
        runtimes = runtime_files(files)
        raise Error, "No runtime Dockerfiles in #{directory}" if runtimes.empty?

        variable, checksum = VARIABLES.fetch(engine)
        versions = runtimes.map do |path, text|
          version = Version.new(field(text, variable))
          raise Error, "Version #{version} does not belong to #{path}" unless version.series == name
          if checksum && !/\A[a-f0-9]{64}\z/.match?(field(text, checksum))
            raise Error, "Invalid checksum in #{path}"
          end
          version.to_s
        end.uniq
        raise Error, "Conflicting versions in #{directory}: #{versions.join(", ")}" unless versions.size == 1

        pinned = runtimes.values.any? { |text| text.match?(%r{https://github\.com/ruby/ruby/archive/[a-f0-9]{40}\.tar\.gz}) }
        series = Series.new(engine: engine, name: name, version: Version.new(versions.first), files: files, pinned: pinned)
        @series[[engine, name]] = series
      end
    end

    def prepare(change, source)
      template = @series.fetch([change.engine, change.template])
      raise Error, "Cannot update or copy manually pinned #{template.engine} #{template.name}" if template.pinned

      source.resolve(change.release, required_assets(template))
      name = change.release.version.series
      old_prefix = "src/engines/#{change.engine}/#{template.name}/"
      new_prefix = "src/engines/#{change.engine}/#{name}/"
      addition = change.kind != "update"
      if addition && File.exist?(File.join(@root, new_prefix))
        raise Error, "Series already exists: #{new_prefix}"
      end

      files = template.files.to_h do |path, text|
        target = addition ? path.sub(old_prefix, new_prefix) : path
        updated = rewrite(text, path, template, change.release)
        mode = @modes.fetch(path) { File.stat(File.join(@root, path)).mode & 0o777 }
        write(target, updated, new_file: addition, mode: mode)
        [target, updated]
      end
      if addition
        gemfile = "gemfiles/#{change.engine}-#{template.name}.gemfile"
        write("gemfiles/#{change.engine}-#{name}.gemfile", read(gemfile), new_file: true)
        MATRICES.each { |path| duplicate_matrix(path, change.engine, template.name, name) }
      end
      @series[[change.engine, name]] = Series.new(engine: change.engine, name: name, version: change.release.version, files: files, pinned: false)
    end

    def validate
      @series.each_value do |series|
        next unless series.files.keys.any? { |path| @edits.key?(path) }

        read("gemfiles/#{series.engine}-#{series.name}.gemfile")
        series.files.each_value do |text|
          text.scan(%r{^FROM ghcr\.io/datadog/images-rb/engines/(\w+):(\d+\.\d+)-([\w.-]+)(?:\s|$)}) do |engine, name, suffix|
            read("src/engines/#{engine}/#{name}/Dockerfile.#{suffix.tr("-", ".")}")
          end
        end
        MATRICES.each do |path|
          entries = matrix(read(path))
          targets = entries.select { |entry| entry["engine"] == series.engine && entry["version"] == series.name }
          expected = series.files.keys.filter_map do |file|
            basename = File.basename(file)
            if path == MATRICES.first
              basename.delete_prefix("Dockerfile.") if runtime?(file)
            elsif basename.end_with?(".gcc", ".clang")
              basename.split(".")[1]
            end
          end.uniq.sort
          actual = targets.map { |entry| entry.fetch("libc") }.sort
          raise Error, "Matrix does not match #{series.engine} #{series.name}: #{path}" unless actual == expected

          targets.each do |entry|
            raise Error, "Empty architecture list in #{path}" unless entry["arch"].is_a?(Array) && !entry["arch"].empty?
            suffixes = (path == MATRICES.first) ? [""] : [".gcc", ".clang"]
            suffixes.each { |suffix| read("src/engines/#{series.engine}/#{series.name}/Dockerfile.#{entry.fetch("libc")}#{suffix}") }
          end
        end
      end
      @edits
    end

    def apply
      @originals.each do |path, original|
        absolute = File.join(@root, path)
        current = File.exist?(absolute) ? File.binread(absolute) : nil
        raise Error, "File changed since planning: #{path}" unless current == original
      end
      staged = []
      begin
        @edits.each do |path, text|
          absolute = File.join(@root, path)
          FileUtils.mkdir_p(File.dirname(absolute))
          temporary = Tempfile.new(".engine-update-", File.dirname(absolute))
          staged << [temporary, absolute]
          temporary.binmode
          temporary.write(text)
          temporary.flush
          temporary.chmod(@modes.fetch(path) { File.exist?(absolute) ? File.stat(absolute).mode & 0o777 : 0o644 })
        end
        staged.each { |temporary, absolute| File.rename(temporary.path, absolute) }
      ensure
        staged.each { |temporary, _| temporary.close! }
      end
    end

    private

    def read(path)
      return @edits[path] if @edits.key?(path)

      @originals[path] ||= File.binread(File.join(@root, path))
    rescue Errno::ENOENT
      raise Error, "Missing repository file: #{path}"
    end

    def write(path, text, new_file: false, mode: nil)
      if new_file
        raise Error, "Target already exists: #{path}" if @edits.key?(path) || File.exist?(File.join(@root, path))

        @originals[path] = nil
      else
        read(path)
      end
      @edits[path] = text unless text == @originals[path]
      @modes[path] = mode if mode
    end

    def runtime?(path)
      /\ADockerfile\.[^.]+\z/.match?(File.basename(path))
    end

    def runtime_files(files)
      files.select { |path, _| runtime?(path) }
    end

    def assignment(name)
      /^([ \t]*(?:ENV[ \t]+)?#{Regexp.escape(name)}=)(["']?)([^\s"'\\]+)\2(?=[ \t\\]*$)/
    end

    def field(text, name)
      matches = text.scan(assignment(name))
      raise Error, "Expected one #{name} declaration, found #{matches.size}" unless matches.size == 1

      matches.first[2]
    end

    def replace_field(text, name, value)
      field(text, name)
      text.sub(assignment(name)) { "#{$1}#{$2}#{value}#{$2}" }
    end

    def required_assets(series)
      runtime_files(series.files).values.flat_map do |text|
        case series.engine
        when "ruby"
          formats = text.scan(/curl[^\n]* -o ruby\.(tar\.(?:xz|gz|bz2))/).flatten.uniq
          raise Error, "Expected one Ruby archive format in #{series.name}" unless formats.size == 1

          formats
        when "jruby"
          raise Error, "Unrecognised JRuby archive recipe" unless text.include?("/jruby-dist-${JRUBY_VERSION}-bin.tar.gz")

          ["tar.gz"]
        when "truffleruby"
          raise Error, "Unrecognised TruffleRuby archive recipe" unless text.include?("truffleruby-community-${TRUFFLERUBY_VERSION}-linux-${arch}.tar.gz")

          hashes = text.scan(TRUFFLE_HASH)
          raise Error, "Missing TruffleRuby architecture checksums" unless hashes.map { |match| match[1] }.sort == ARCHES.keys.sort

          hashes.map do |_, cpu, arch, _|
            raise Error, "Mismatched TruffleRuby architecture: #{cpu}/#{arch}" unless ARCHES.fetch(cpu) == arch

            arch
          end
        end
      end.uniq
    end

    def rewrite(text, path, template, release)
      engine = template.engine
      name = release.version.series
      text = text.dup
      if runtime?(path)
        variable, checksum = VARIABLES.fetch(engine)
        text = replace_field(text, variable, release.version.to_s)
        if engine == "ruby"
          text = replace_field(text, "RUBY_MAJOR", name)
          format = text[/curl[^\n]* -o ruby\.(tar\.(?:xz|gz|bz2))/, 1]
          text = replace_field(text, checksum, release.assets.fetch(format).sha256)
        elsif engine == "jruby"
          text = replace_field(text, checksum, release.assets.fetch("tar.gz").sha256)
        else
          text.gsub!(TRUFFLE_HASH) { "#{$1}#{release.assets.fetch($3).sha256}" }
        end
      end
      text.gsub!(%r{(^FROM ghcr\.io/datadog/images-rb/engines/#{engine}:)#{Regexp.escape(template.name)}(?=[-\s])}) { "#{$1}#{name}" }
      # Some JRuby stage names still contain the version from the original recipe.
      text.scan(/^FROM \S+ AS (#{engine}-(\S+?)(-jre\d+))$/).each do |stage, version, java|
        Version.new(version)
        replacement = "#{engine}-#{release.version.to_s.downcase}#{java}"
        text.gsub!(/(\bAS |\bFROM |--from=)#{Regexp.escape(stage)}(?=\s|$)/) { "#{$1}#{replacement}" }
      end
      text
    end

    def matrix(text)
      YAML.safe_load(text).fetch("jobs").fetch("build").fetch("strategy").fetch("matrix").fetch("include")
    rescue Psych::Exception, KeyError => e
      raise Error, "Invalid build matrix: #{e.message}"
    end

    def duplicate_matrix(path, engine, previous, name)
      text = read(path)
      entries = matrix(text).select { |entry| entry["engine"] == engine && entry["version"] == previous }
      copies = 0
      updated = text.gsub(/^([ \t]*)- engine: #{Regexp.escape(engine)}\n\1  version: "#{Regexp.escape(previous)}"\n(?:\1  [^\n]*\n)*/) do |block|
        copies += 1
        block + block.sub("version: \"#{previous}\"", "version: \"#{name}\"")
      end
      raise Error, "Could not copy #{engine} #{previous} matrix entries in #{path}" unless copies == entries.size

      write(path, updated)
    end
  end
end
