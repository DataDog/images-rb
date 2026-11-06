# ruby-version-min: 1.8.7

require "minitest/autorun"

class TestTruffleRuby < Minitest::Test
  def setup
    skip "TruffleRuby images only" unless ENV["IMAGE_ENGINE"] == "truffleruby"

    require "bundler"
    require "open3"
    require "rbconfig"
  end

  def test_native_runtime
    assert_equal("truffleruby", RUBY_ENGINE)
    assert_equal(ENV.fetch("TRUFFLERUBY_VERSION"), RUBY_ENGINE_VERSION)
    assert(TruffleRuby.native?)
  end

  def test_runtime_libraries
    run!(RbConfig.ruby, "-e", <<-RUBY)
      require "openssl"
      require "psych"
      require "zlib"

      abort "YAML round trip failed" unless Psych.load(Psych.dump({"smoke" => true}))["smoke"]
      abort "compression round trip failed" unless Zlib::Inflate.inflate(Zlib::Deflate.deflate("smoke")) == "smoke"

      store = OpenSSL::X509::Store.new
      store.set_default_paths
      roots = File.read("/etc/ssl/certs/ca-certificates.crt").scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
      abort "system CA trust unavailable" unless roots.any? { |pem| store.verify(OpenSSL::X509::Certificate.new(pem)) }
    RUBY
  end

  def test_native_extension
    skip "compiler images only" unless [".gcc", ".clang"].include?(ENV["IMAGE_COMPILER"])

    require "tmpdir"
    require "fileutils"

    Dir.mktmpdir("truffleruby-extension") do |dir|
      FileUtils.cp(Dir.glob("test/fixtures/extensions/smoke/*"), dir)
      run!({"CC" => RbConfig::CONFIG["CC"]}, RbConfig.ruby, "extconf.rb", :chdir => dir)
      run!("make", :chdir => dir)
      run!(RbConfig.ruby, "-I", dir, "-rsmoke", "-e", "abort unless Smoke.answer == 42")
    end
  end

  private

  def run!(*args)
    output, status = Bundler.with_unbundled_env { Open3.capture2e(*args) }
    assert(status.success?, "#{status}: #{output}")
  end
end
