# ruby-version-min: 1.8.7

require "bundler"
require "minitest/autorun"
require "open3"
require "tmpdir"

class TestDatabaseGems < Minitest::Test
  def setup
    ruby_version = Gem::Version.new(RUBY_VERSION)
    skip "database gem coverage starts at Ruby 2.5" unless Gem::Requirement.new(">= 2.5").satisfied_by?(ruby_version)
    skip "database gems require CRuby" unless ENV["IMAGE_ENGINE"] == "ruby"
    skip "database gems require a compiler image" unless [".gcc", ".clang"].include?(ENV["IMAGE_COMPILER"])
  end

  def test_sqlite3
    ruby_version = Gem::Version.new(RUBY_VERSION)
    version = case ruby_version
    when Gem::Requirement.new("~> 2.5.0") then "1.3.13"
    when Gem::Requirement.new(">= 2.6", "< 3.0") then "1.4.4"
    when Gem::Requirement.new(">= 3.0", "< 3.4") then "1.6.6"
    when Gem::Requirement.new(">= 3.4", "< 4.0") then "1.7.3"
    when Gem::Requirement.new(">= 4.0", "< 4.1") then "2.8.1"
    end

    with_gem_home do |env|
      install_gem(env, "sqlite3", version, true)
      run!(env, [Gem.ruby, "-rsqlite3", "-e", "db = SQLite3::Database.new(':memory:'); abort unless db.get_first_value('SELECT 1') == 1"])
    end
  end

  def test_mysql2
    ruby_version = Gem::Version.new(RUBY_VERSION)
    needs_bigdecimal = Gem::Requirement.new(">= 3.4").satisfied_by?(ruby_version)
    bigdecimal_version = ruby_version >= Gem::Version.new("4.0") ? "4.1.2" : "3.1.8"

    with_gem_home do |env|
      install_gem(env, "bigdecimal", bigdecimal_version, false) if needs_bigdecimal
      install_gem(env, "mysql2", "0.5.7", false)
      requirements = ["-rmysql2"]
      requirements.unshift("-rbigdecimal") if needs_bigdecimal
      run!(env, [Gem.ruby] + requirements + ["-e", "abort unless Mysql2::Client.info[:version]"])
    end
  end

  def test_pg
    ruby_version = Gem::Version.new(RUBY_VERSION)
    pg_version = ENV["IMAGE_LIBC"] == "centos" ? "1.1.4" : "1.5.9"
    needs_bigdecimal =
      Gem::Requirement.new("< 1.2.0").satisfied_by?(Gem::Version.new(pg_version)) &&
      Gem::Requirement.new(">= 3.4").satisfied_by?(ruby_version)
    bigdecimal_version = ruby_version >= Gem::Version.new("4.0") ? "4.1.2" : "3.1.8"

    with_gem_home do |env|
      # pg < 1.2.0 loads but does not declare bigdecimal.
      install_gem(env, "bigdecimal", bigdecimal_version, false) if needs_bigdecimal
      install_gem(env, "pg", pg_version, true)
      requirements = ["-rpg"]
      requirements.unshift("-rbigdecimal") if needs_bigdecimal
      run!(env, [Gem.ruby] + requirements + ["-e", "abort unless PG.library_version > 0"])
    end
  end

  private

  def with_gem_home
    Bundler.with_unbundled_env do
      Dir.mktmpdir("images-rb-gems") do |gem_home|
        env = {
          "GEM_HOME" => gem_home,
          "GEM_PATH" => gem_home,
          "PATH" => "#{gem_home}/bin:#{ENV["PATH"]}"
        }
        yield env
      end
    end
  end

  def install_gem(env, name, version, ruby_platform)
    command = [Gem.ruby, "-S", "gem", "install", name, "-v", version, "--no-document"]
    command.concat(["--platform", "ruby"]) if ruby_platform
    run!(env, command)
  end

  def run!(env, command)
    stdin, stdout, stderr, wait_thread = Open3.popen3(env, *command)
    stdin.close
    output = stdout.read + stderr.read
    assert(wait_thread.value.success?, "#{command.join(" ")} failed:\n#{output}")
  end
end
