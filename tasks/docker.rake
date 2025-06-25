# frozen_string_literal: true

# @type self: Rake::DSL

# TODO: use rake dependency + satisfaction mechanism via `needs?`
# See: https://github.com/ruby/rake/blob/03cb03474b4eb008b2d62ad96d07de0d6239c7ab/lib/rake/file_task.rb#L16

namespace :docker do
  # 1980-01-01 00:00:00 UTC
  NINETYEIGHTY = 315532800

  def source_date_epoch
    NINETYEIGHTY
  end

  def repro_run_key
    @repro_run_key ||= File.exist?(".repro_run_key") ? Integer(File.read(".repro_run_key").strip) : 0
  end

  def repository # TODO: rename to registry/registry host/user/path
    "ghcr.io/datadog/images-rb"
  end

  def targets
    @targets ||= Dir.glob("src/**/Dockerfile*").map do |f|
      dockerfile = f
      context = File.dirname(dockerfile)

      if (m = context.match(/\/((?:v?)\d+(?:\.\d+|$)+)$/))
        tag = m[1] + File.basename(dockerfile).sub(/Dockerfile(?:.*)$/) { |m| m.sub("Dockerfile", "").tr(".", "-") }
        image = "#{repository}/#{File.dirname(context).sub(/^src\//, "")}"
      else
        tag = "latest"
        image = "#{repository}/#{context.sub(/^src\//, "")}".sub(/Dockerfile(?:.*)$/) { |m| m.sub("Dockerfile", "").tr(".", "-") }
      end

      platforms = File.read(dockerfile).lines.select { |l| l =~ /^\s*#\s*platforms:/ }.map { |l| l =~ /platforms: (.*)/ && $1 }

      targets = [
        {
          dockerfile: dockerfile,
          context: context,
          platforms: platforms,
          image: image, # TODO: rename to repository
          tag: tag
          # TODO: rename to image/tag/tagged_image/name/alias: "#{repo}:#{tag}"
        }
      ]

      strip_tags = File.read(dockerfile).lines.select { |l| l =~ /^\s*#\s*strip-tags:/ }.map { |l| l =~ /strip-tags: (.*)/ && $1 }
      if strip_tags.any?
        stripped_tag = strip_tags.each_with_object(tag.dup) { |t, r| r.gsub!(/-#{t}/, "") }
        targets << {
          dockerfile: dockerfile,
          context: context,
          platforms: platforms,
          image: image,
          tag: stripped_tag,
          aliasing: tag
        }
      end

      append_tags = File.read(dockerfile).lines.select { |l| l =~ /^\s*#\s*append-tags:/ }.map { |l| l =~ /append-tags: (.*)/ && $1 }
      if append_tags.any?
        append_tags.each do |t|
          targets << {
            dockerfile: dockerfile,
            context: context,
            platforms: platforms,
            image: image,
            tag: "#{tag}-#{t}",
            aliasing: tag
          }
        end
      end

      targets
    end.flatten
  end

  def dependencies
    @dependencies ||= Dir.glob("src/**/Dockerfile*").each_with_object({}) do |path, h|
      h[path] = File.read(path).each_line.with_object([]) { |l, a| l =~ /^FROM (\S+)(?:\s+AS|\s*$)/ && a << $1 }
    end
  end

  def local_dependencies
    @local_dependencies ||= dependencies.each_with_object({}) { |(k, v), h| h[k] = v.select { |from| from.start_with?(repository) } }
  end

  def target_for(args)
    targets_for(args).tap { |a| a.size > 1 and fail "multiple args passed to task" }.first
  end

  def glob_match?(pattern, str)
    re = Regexp.new("^#{Regexp.escape(pattern).gsub("\\*\\*", "[^:]*?").gsub("\\*", "[^/:]*?")}$")

    !!(str =~ re)
  end

  def targets_for(args)
    images = args.to_a

    images = ["**:*"] if images.empty?

    images.map do |image|
      image = "#{repository}/#{image}" unless image.start_with?(repository)

      found = targets.select { |e| glob_match?(image, "#{e[:image]}:#{e[:tag]}") }

      fail "#{image} not found" if found.nil?

      found
    end.flatten
  end

  def dockerfiles_for(*images)
    images.map do |image|
      targets.each_with_object([]) { |t, a| a << t[:dockerfile] if "#{t[:image]}:#{t[:tag]}" == image }
    end.flatten
  end

  def satisfied?(result, deps = [])
    result_time = case result
    when String
      File.ctime(result).to_datetime
    when Proc
      result.call
    else
      raise ArgumentError, "invalid type: #{dep.class}"
    end

    return false if result_time.nil?
    return true if deps.empty?

    deps.map do |dep|
      dep_time = case dep
      when String
        File.ctime(dep).to_datetime
      when Proc
        dep.call
      else
        raise ArgumentError, "invalid type: #{dep.class}"
      end

      result_time > dep_time
    end.reduce(:&)
  end

  PLATFORMS = [
    "linux/x86_64",
    "linux/aarch64"
  ]

  def docker_platforms
    if (p = ENV["PLATFORM"])
      return p.split(",")
    end

    if RUBY_PLATFORM =~ /^(?:universal\.|)(x86_64|aarch64|arm64)/
      cpu = $1.sub(/arm64(:?e|)/, "aarch64")
    else
      raise ArgumentError, "unsupported platform: #{RUBY_PLATFORM}"
    end

    os = "linux"

    ["#{os}/#{cpu}"]
  end

  def docker_platform
    docker_platforms.tap { |a| a.size > 1 and fail "multiple platforms passed to task" }.first
  end

  def image_time(image)
    require "time"

    last_tag_time = `docker image inspect -f '{{ .Metadata.LastTagTime }}' '#{image}' 2>/dev/null`.chomp

    if $?.to_i == 0
      # "0001-01-01 00:00:00 +0000 UTC"
      last_tag_time.sub!(/^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})(\s+)/, "\\1.0\\2")

      DateTime.strptime(last_tag_time, "%Y-%m-%d %H:%M:%S.%N %z")
    end
  end

  def volume_time(volume)
    require "time"

    volume_creation_time = `docker volume inspect -f '{{ .CreatedAt }}' '#{volume}' 2>/dev/null`.chomp

    if $?.to_i == 0
      volume_creation_time.sub!(/^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})(\s+)/, "\\1.0\\2")

      DateTime.strptime(volume_creation_time, "%Y-%m-%dT%H:%M:%S.%N %z")
    end
  end

  desc <<~DESC
    List image targets.

    Accepts globs as argument, e.g 'list[**:*]' will show everything.
  DESC
  task :list do |_, args|
    targets_for(args).each do |image|
      puts "#{image[:image]}:#{image[:tag]}"
    end
  end

  namespace :list do
    desc <<~DESC
      List detailed image targets as JSON.

      Accepts globs as argument, e.g 'list:json[**:*]' will show everything.
    DESC
    task :json do |_, args|
      require "json"

      puts JSON.pretty_generate(targets_for(args))
    end
  end

  desc <<~DESC
    Pull image(s).

    Accepts globs as argument, e.g 'pull[**:*]' will pull everything.

    Considers these env vars:
    - PLATFORM=linux/x86_64: platform to pull. Defaults to current system platform.
  DESC
  task :pull do |_, args|
    targets = targets_for(args)

    targets.each do |target|
      image = target[:image]
      tag = target[:tag]
      platform = docker_platform

      sh "docker pull --platform #{platform} #{image}:#{tag} || true"
    end
  end

  desc <<~DESC
    Build image(s).

    Accepts globs as argument, e.g 'build[**:*]' will build everything.

    Considers these env vars:
    - PLATFORM=linux/x86_64,linux/aarch64: comma-separated list of platforms to build for. Defaults to current system platform. Building multiplatform requires containerd Docker storage driver.
    - FORCE=true: act as if dependencies were obsolete.
    - PUSH=true: build and push to image registry.
  DESC
  task :build do |_, args|
    targets = targets_for(args)

    targets.each do |target|
      dockerfile = target[:dockerfile]
      context = target[:context]
      image = target[:image]
      tag = target[:tag]
      platforms = docker_platforms
      push = ENV["PUSH"] == "true"
      force = ENV["FORCE"] == "true"

      deps = [
        dockerfile
      ] + dockerfiles_for(*local_dependencies[dockerfile])

      compatible_platforms = deps.map do |dep|
        File.read(dep).lines.select { |l| l =~ /^\s*#\s*platforms:/ }.map { |l| l =~ /platforms: (.*)/ && $1 }
      end.flatten

      if compatible_platforms.any?
        incompatible_platforms = platforms - compatible_platforms
        incompatible_platforms.each do |platform|
        warn "skip build: dockerfile: #{dockerfile.inspect}, incompatible platform: #{platform.inspect}, compatible platforms: #{compatible_platforms.inspect}"
        end

        platforms -= incompatible_platforms
      end

      next if platforms.empty?

      # TODO: consider platforms for dependencies as well
      local_dependencies[dockerfile].each { |dep| Rake::Task[:"docker:build"].execute(Rake::TaskArguments.new([], [dep])) }

      next if !force && satisfied?(-> { image_time("#{image}:#{tag}") }, deps)

      sh "docker buildx build --platform #{platforms.join(",")} --cache-from=type=registry,ref=#{image}:#{tag} --output=type=image,push=#{push} --build-arg REPRO_RUN_KEY=#{repro_run_key} --build-arg SOURCE_DATE_EPOCH=#{source_date_epoch} --build-arg BUILDKIT_INLINE_CACHE=1 -f #{dockerfile} -t #{image}:#{tag} #{context}"
    end
  end

  desc <<~DESC
    Remove image(s).

    Accepts globs as argument, e.g 'remove[**:*]' will remove everything.
  DESC
  task :remove do |_, args|
    targets = targets_for(args)

    targets.each do |target|
      image = target[:image]
      tag = target[:tag]

      sh "docker image rm #{image}:#{tag} || true"
    end
  end

  desc <<~DESC
    Run container with default CMD.

    Accepts globs as argument, e.g 'cmd[**:*]', but fails with more than one match.

    Considers these env vars:
    - PLATFORM=linux/x86_64: platform to run. Defaults to current system platform.
  DESC
  task cmd: :build do |_, args|
    target = target_for(args)

    image = target[:image]
    tag = target[:tag]
    platform = docker_platform

    exec "docker run --rm -it --platform #{platform} -v #{Dir.pwd}:#{Dir.pwd} -w #{Dir.pwd} #{image}:#{tag}"
  end

  desc <<~DESC
    Run container with shell.

    Accepts globs as argument, e.g 'shell[**:*]', but fails with more than one match.

    Considers these env vars:
    - PLATFORM=linux/x86_64: platform to run. Defaults to current system platform.
  DESC
  task shell: :build do |_, args|
    target = target_for(args)

    image = target[:image]
    tag = target[:tag]
    platform = docker_platform

    exec "docker run --rm -it --platform #{platform} -v #{Dir.pwd}:#{Dir.pwd} -w #{Dir.pwd} #{image}:#{tag} /bin/sh"
  end

  desc <<~DESC
    Run container with shell.

    Accepts globs as argument, e.g 'irb[**:*]', but fails with more than one match.

    Considers these env vars:
    - PLATFORM=linux/x86_64: platform to run. Defaults to current system platform.
  DESC
  task irb: :build do |_, args|
    target = target_for(args)

    image = target[:image]
    tag = target[:tag]
    platform = docker_platform

    exec "docker run --rm -it --platform #{platform} -v #{Dir.pwd}:#{Dir.pwd} -w #{Dir.pwd} #{image}:#{tag} irb"
  end
end
