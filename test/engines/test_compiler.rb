# ruby-version-min: 1.8.7

require "minitest/autorun"
require "tmpdir"

class TestCompiler < Minitest::Test
  def setup
    skip "compiler contract applies to CRuby and TruffleRuby images" unless ["ruby", "truffleruby"].include?(ENV["IMAGE_ENGINE"])
    skip "image variant is unknown" unless ENV.key?("IMAGE_COMPILER")
  end

  def test_runtime_has_no_compiler
    skip "compiler image" unless ENV["IMAGE_COMPILER"] == ""

    # Check versioned and target-prefixed binaries too, beyond the gcc symlink.
    paths = Dir["/usr/bin/*"] + Dir["/usr/local/bin/*"] + Dir["/opt/rh/*/root/usr/bin/*"]
    compilers = paths.select do |path|
      File.executable?(path) && File.basename(path) =~ /\A(?:\w+-)*(?:gcc|g\+\+|clang|clang\+\+|cc|c\+\+)(?:-[\d.]+)?\z/
    end
    assert_equal([], compilers)
  end

  def test_native_compilation
    skip "runtime image" unless [".gcc", ".clang"].include?(ENV["IMAGE_COMPILER"])
    skip "legacy musl compiler selection is unchanged" if ENV["IMAGE_LIBC"] == "musl" && Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.5")

    compiler = (ENV["IMAGE_COMPILER"] == ".clang") ? "clang" : "gcc"
    # Ruby's build configuration invokes gcc in every compiler variant.
    output = `gcc --version 2>&1`
    assert($?.success?, output)
    assert_match(/#{compiler}/i, output)

    Dir.mktmpdir("images-rb-compiler") do |dir|
      source = File.join(dir, "main.c")
      binary = File.join(dir, "main")
      File.open(source, "w") { |file| file << "int main(void) { return 0; }\n" }
      assert(system("gcc", source, "-o", binary), "#{compiler} could not compile and link")
      assert(system(binary), "compiled programme could not run")
    end
  end

  def test_cpp_compilation
    skip "C++ compiler image required" unless ENV["IMAGE_COMPILER"] == ".gcc" || (ENV["IMAGE_ENGINE"] == "truffleruby" && ENV["IMAGE_COMPILER"] == ".clang")

    Dir.mktmpdir("images-rb-cpp") do |dir|
      source = File.join(dir, "main.cpp")
      binary = File.join(dir, "main")
      File.open(source, "w") do |file|
        file << "#include <string>\nint main() { return std::string(\"test\").size() == 4 ? 0 : 1; }\n"
      end
      assert(system("g++", source, "-o", binary), "g++ could not compile and link")
      assert(system(binary), "compiled C++ programme could not run")
    end
  end

  # Gems such as psych and fiddle link against the runtime libraries Ruby
  # itself uses. The base images purge the development packages after
  # building Ruby, so compiler images must install them again.
  def test_headers_for_ruby_runtime_libraries
    skip "CRuby images only" unless ENV["IMAGE_ENGINE"] == "ruby"
    skip "compiler image" unless [".gcc", ".clang"].include?(ENV["IMAGE_COMPILER"])

    Dir.mktmpdir("images-rb-headers") do |dir|
      source = File.join(dir, "headers.c")
      headers = %w[ffi.h openssl/ssl.h yaml.h zlib.h]
      File.open(source, "w") do |file|
        headers.each { |header| file << "#include <#{header}>\n" }
        file << "int main(void) { return 0; }\n"
      end
      output = `gcc -c #{source} -o #{File.join(dir, "headers.o")} 2>&1`

      assert_predicate($?, :success?, output)
    end
  end
end
