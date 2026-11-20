# frozen_string_literal: true

# ruby-version-min: 2.3.0

namespace :mirror do
  desc "Check the external image inventory against Dockerfiles"
  task :check do
    fail "mirror tasks require Ruby 3.3 or newer" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")

    require_relative "mirror/refresh"
    ImagesMirror::Inventory.new("mirror.yml").check(Dir.pwd)
  end

  desc "Check upstream digests and platforms without copying or writing a lock"
  task inspect: :check do
    ImagesMirror::Refresh.new(ImagesMirror::Inventory.new("mirror.yml")).run(nil, check: true)
  end

  desc "Copy and verify upstream images; write mirror.lock.yml only on complete success"
  task refresh: :check do
    ImagesMirror::Refresh.new(ImagesMirror::Inventory.new("mirror.yml")).run("mirror.lock.yml")
  end

  desc "Test mirror refresh without registry access (requires Ruby 3.3 or newer)"
  task :test do
    fail "mirror:test requires Ruby 3.3 or newer" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")

    ruby File.expand_path("mirror/test/mirror_test.rb", __dir__)
  end
end
