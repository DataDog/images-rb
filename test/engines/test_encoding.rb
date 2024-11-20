require "minitest/autorun"

# polyfill for Ruby 2.2 and down, used by minitest
unless "".respond_to?(:match?)
  String.instance_eval do
    def match?(other)
      (Regexp === other) ? other.match?(self) : (self == other)
    end
  end
end

class TestEncoding < Minitest::Test
  def test_utf8_lang
    assert_equal("en_US.UTF-8", ENV["LANG"])
  end

  def test_utf8_string
    assert_equal(Encoding::UTF_8, "".encoding)
  end

  def test_read_utf8
    contents = File.read("test/fixtures/encoding/utf-8.txt")

    assert_equal(Encoding::UTF_8, contents.encoding)
    assert_equal("\u2705\n", contents)
  end
end
