# ruby-version-min: 1.8.7

require "minitest/autorun"

class TestAsan < Minitest::Test
  def setup
    skip "ASan images only" unless ENV["IMAGE_SANITIZER"] == "address"

    require "fileutils"
    require "open3"
    require "rbconfig"
    require "tmpdir"
    require "timeout"
  end

  def test_native_extension
    assert_match(/clang/, RbConfig::CONFIG["CC"])

    with_extension do |dir|
      [["read_byte", "asan_probe.c"], ["read_byte_cpp", "cpp_probe.cpp"]].each do |method, source|
        output, status = capture(RbConfig.ruby, "-I", dir, "-rasan_probe", "-e", "abort unless AsanProbe.#{method}(0) == 0")

        assert_predicate(status, :success?, output)

        output, status = capture(RbConfig.ruby, "-I", dir, "-rasan_probe", "-e", "AsanProbe.#{method}(8)")

        refute_predicate(status, :success?, output)
        assert_match(/AddressSanitizer: heap-buffer-overflow/, output)
        assert_match(/#{Regexp.escape(source)}:\d+/, output)
      end
    end
  end

  def test_leak_detection
    with_extension do |dir|
      env = {"ASAN_OPTIONS" => "detect_leaks=1", "RUBY_FREE_AT_EXIT" => "1"}
      output, status = capture(env, RbConfig.ruby, "-I", dir, "-rasan_probe", "-e", "AsanProbe.leak_memory")

      refute_predicate(status, :success?, output)
      assert_match(/LeakSanitizer: detected memory leaks/, output)
      assert_match(/Direct leak of 1337 byte/, output)
      assert_match(/asan_probe\.c:\d+/, output)
    end
  end

  def test_gc_threads_fibres_and_fork
    run_ruby(<<-RUBY)
      require "timeout"
      Timeout.timeout(30) do
        threads = Array.new(4) do
          Thread.new do
            fibre = Fiber.new do
              10.times do
                objects = Array.new(1000) { "asan" * 100 }
                GC.start
                Fiber.yield objects.last.size
              end
            end
            10.times { abort "fibre lost state" unless fibre.resume == 400 }
          end
        end
        threads.each(&:value)

        ready = Queue.new
        worker = Thread.new { ready << true; sleep }
        ready.pop
        pid = fork do
          Thread.new { GC.start }.value
          exit! 0
        end
        Process.wait(pid)
        abort "forked child failed" unless $?.success?
        worker.kill.join
      end
    RUBY
  end

  def test_instrumented_libraries
    run_ruby(<<-RUBY)
      require "openssl"
      require "psych"
      require "fiddle"

      abort "YAML round trip failed" unless Psych.safe_load(Psych.dump({"asan" => true}))["asan"]
      abort "OpenSSL digest failed" unless OpenSSL::Digest::SHA256.hexdigest("asan").size == 64
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      roots = File.read("/etc/ssl/certs/ca-certificates.crt").scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
      abort "system CA trust unavailable" unless roots.any? { |pem| store.verify(OpenSSL::X509::Certificate.new(pem)) }

      maps = File.read("/proc/self/maps")
      %w[libssl.so libcrypto.so libyaml].each do |library|
        abort "uninstrumented library: " + library unless maps.include?("/opt/asan/lib/" + library)
      end
      %w[/opt/asan/lib/libssl.so /opt/asan/lib/libcrypto.so /opt/asan/lib/libyaml.so].each do |library|
        symbols = IO.popen(["nm", "-D", library], &:read)
        abort "missing ASan instrumentation: " + library unless symbols.include?("__asan_")
      end

      callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INT]) { |n| n + 1 }
      function = Fiddle::Function.new(callback, [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      abort "libffi callback failed" unless function.call(41) == 42
    RUBY
  end

  def test_yjit
    run_ruby('abort "YJIT unavailable" unless RubyVM::YJIT.enabled?', ["--yjit"])
  end

  private

  def with_extension
    Dir.mktmpdir("asan-extension") do |dir|
      FileUtils.cp(Dir.glob("test/fixtures/extensions/asan/*"), dir)
      Dir.chdir(dir) do
        output, status = capture(RbConfig.ruby, "extconf.rb")

        assert_predicate(status, :success?, output)

        output, status = capture("make")

        assert_predicate(status, :success?, output)
      end
      yield dir
    end
  end

  def run_ruby(source, options = [])
    output, status = capture(*([RbConfig.ruby] + options + ["-e", source]))

    assert_predicate(status, :success?, "#{status}: #{output}")
  end

  def capture(*args)
    return capture_unbundled(*args) unless defined?(Bundler)

    # Inspect bundled extensions even when absent from the test bundle.
    Bundler.with_unbundled_env { capture_unbundled(*args) }
  end

  def capture_unbundled(*args)
    # Ruby 1.8 must parse this file, even though ASan tests only run on 3.4+.
    options = {:pgroup => true} # rubocop:disable Style/HashSyntax
    Open3.popen2e(*(args + [options])) do |input, output, process|
      input.close
      finished = false
      begin
        result = Timeout.timeout(120) { [output.read, process.value] }
        finished = true
        result
      ensure
        # Kill the whole group before Open3 joins it, including forked children.
        unless finished
          begin
            Process.kill("KILL", -process.pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
  end
end
