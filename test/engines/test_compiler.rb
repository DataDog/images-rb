# ruby-version-min: 1.8.7

require "minitest/autorun"
require "tmpdir"

class TestCompiler < Minitest::Test
  def setup
    skip "compiler contract applies to CRuby images" unless ENV["IMAGE_ENGINE"] == "ruby"
    skip "image variant is unknown" unless ENV.key?("IMAGE_COMPILER")
  end

  def test_runtime_has_no_compiler
    skip "compiler image" unless ENV["IMAGE_COMPILER"] == ""

    # Check versioned and target-prefixed binaries too, not just the gcc symlink.
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
    # Ruby's build configuration invokes gcc, including in Clang variants.
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

  def test_gcc_cpp_compilation
    skip "GCC image required" unless ENV["IMAGE_COMPILER"] == ".gcc"

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
end
