# Shared test files must parse on Ruby 1.8, even when their tests are skipped.
# rubocop:disable Style/HashSyntax
require "minitest/autorun"

class TestMusl < Minitest::Test
  def setup
    skip "CRuby musl images only" unless RUBY_PLATFORM.include?("musl") && RUBY_VERSION >= "2.1"

    require "open3"
    require "rbconfig"
  end

  def test_runtime_extensions
    run_ruby(<<-RUBY)
      require "openssl"
      require "psych"
      require "readline"
      require "fiddle"
      require "zlib"
      require "io/console"
      require "gdbm" if RUBY_VERSION < "3.1"

      abort "YAML round trip failed" unless Psych.load(Psych.dump({"smoke" => true}))["smoke"]
      abort "compression round trip failed" unless Zlib::Inflate.inflate(Zlib::Deflate.deflate("smoke")) == "smoke"
      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INT]) { |n| n + 1 }
      function = Fiddle::Function.new(callback, [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      abort "libffi callback failed" unless function.call(41) == 42

      store = OpenSSL::X509::Store.new
      store.set_default_paths
      roots = File.read("/etc/ssl/certs/ca-certificates.crt").scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
      abort "system CA trust unavailable" unless roots.any? { |pem| store.verify(OpenSSL::X509::Certificate.new(pem)) }
    RUBY
  end

  def test_stack_overflow
    # A subprocess makes a native stack crash a test failure, not a lost suite.
    run_ruby(<<-RUBY)
      def recurse(depth)
        recurse(depth + 1)
      rescue SystemStackError
        depth
      end

      abort "main-thread stack exhausted prematurely" if recurse(0) < 1000
    RUBY
  end

  def test_yjit
    skip "YJIT images start at Ruby 3.2" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

    run_ruby('abort "YJIT unavailable" unless RubyVM::YJIT.enabled?', ["--yjit"])
  end

  def test_zjit
    skip "ZJIT images start at Ruby 4.0" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.0")

    run_ruby('abort "ZJIT unavailable" unless RubyVM::ZJIT.enabled?', ["--zjit"])
  end

  def test_native_extension
    compiler = {".gcc" => "gcc", ".clang" => "clang"}[ENV["IMAGE_COMPILER"]]
    skip "compiler images only" unless compiler

    require "tmpdir"
    require "fileutils"

    Dir.mktmpdir("musl-extension") do |dir|
      FileUtils.cp(Dir.glob("test/fixtures/extensions/smoke/*"), dir)
      output, status = capture({"CC" => compiler}, RbConfig.ruby, "extconf.rb", :chdir => dir)
      assert(status.success?, output)
      output, status = capture("make", :chdir => dir)
      assert(status.success?, output)
      output, status = capture(RbConfig.ruby, "-I", dir, "-rsmoke", "-e", "abort unless Smoke.answer == 42")
      assert(status.success?, output)
    end
  end

  private

  def run_ruby(source, options = [])
    output, status = capture(*([RbConfig.ruby] + options + ["-e", source]))
    assert(status.success?, "#{status}: #{output}")
  end

  def capture(*args)
    return Open3.capture2e(*args) unless defined?(Bundler)

    # Inspect image libraries, including bundled gems absent from the test bundle.
    cleaner = Bundler.respond_to?(:with_unbundled_env) ? :with_unbundled_env : :with_clean_env
    Bundler.send(cleaner) { Open3.capture2e(*args) }
  end
end
# rubocop:enable Style/HashSyntax
