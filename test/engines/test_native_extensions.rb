require "minitest/autorun"

# Verifies gems with native extensions against system libraries (pg, mysql2,
# sqlite3) actually compiled and loaded. A no-op unless the gem is present,
# i.e. only exercised when run against gemfiles/ruby-native-ext.gemfile on
# an image that ships the matching dev libs (currently: plain gnu images).
class TestNativeExtensions < Minitest::Test
  def test_pg_loads
    skip "pg not installed" unless gem_available?("pg")

    require "pg"

    assert(defined?(PG::Connection))
  end

  def test_mysql2_loads
    skip "mysql2 not installed" unless gem_available?("mysql2")

    require "mysql2"

    assert(defined?(Mysql2::Client))
  end

  def test_sqlite3_loads
    skip "sqlite3 not installed" unless gem_available?("sqlite3")

    require "sqlite3"

    assert(defined?(SQLite3::Database))
  end

  private

  def gem_available?(name)
    Gem::Specification.find_all_by_name(name).any?
  end
end
