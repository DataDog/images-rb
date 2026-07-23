require "bundler"
require "minitest/autorun"
require "open3"
require "tmpdir"

class TestDatabaseGems < Minitest::Test
  def setup
    skip "database gems require CRuby" unless ENV["IMAGE_ENGINE"] == "ruby"
    skip "database gems require a compiler image" unless [".gcc", ".clang"].include?(ENV["IMAGE_COMPILER"])

    @sqlite_version = case RUBY_VERSION
    when /^2\.5\./ then "1.3.13"
    when /^2\.[6-7]\./ then "1.4.4"
    when /^3\.[0-3]\./ then "1.6.6"
    when /^3\.[4-5]\./, /^4\.0\./ then "1.7.3"
    end
    skip "database gem coverage starts at Ruby 2.5" unless @sqlite_version

    @pg_version = ENV["IMAGE_LIBC"] == "centos" ? "1.1.4" : "1.5.9"
  end

  def test_sqlite3
    with_gem_home do |env|
      install_gem(env, "sqlite3", @sqlite_version, true)
      run!(env, [Gem.ruby, "-rsqlite3", "-e", "db = SQLite3::Database.new(':memory:'); abort unless db.get_first_value('SELECT 1') == 1"])
    end
  end

  def test_mysql2
    with_gem_home do |env|
      install_gem(env, "mysql2", "0.5.7", false)
      run!(env, [Gem.ruby, "-rmysql2", "-e", "abort unless Mysql2::Client.info[:version]"])
    end
  end

  def test_pg
    with_gem_home do |env|
      install_gem(env, "pg", @pg_version, true)
      run!(env, [Gem.ruby, "-rpg", "-e", "abort unless PG.library_version > 0"])
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
