require "minitest/autorun"

class TestPackages < Minitest::Test
  def test_pkg_config_present
    path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).find do |dir|
      File.executable?(File.join(dir, "pkg-config"))
    end

    refute_nil(path, "pkg-config not found on PATH")
    assert(system("pkg-config", "--version", out: File::NULL), "pkg-config --version failed")
  end
end
