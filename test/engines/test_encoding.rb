require "minitest/autorun"

# polyfill for Ruby 2.2 and down, used by minitest assertions
unless "".respond_to?(:match?)
  class String
    def match?(other)
      (Regexp === other) ? other.match?(self) : (self == other)
    end
  end
end

# polyfill for Ruby 1.9.3 and down, used by minitest assertions
unless //.respond_to?(:match?)
  class Regexp
    def match?(other)
      !!match(other)
    end
  end
end

class TestEncoding < Minitest::Test
  def test_utf8_lang
    assert_equal("en_US.UTF-8", ENV["LANG"])
  end

  def test_utf8_string
    skip "missing String#encoding" unless "".respond_to?(:encoding)

    expected = (RUBY_VERSION =~ /^(?:1\.8\.|1\.9\.)/) ? Encoding::US_ASCII : Encoding::UTF_8

    assert_equal(expected, "".encoding)
  end

  def test_read_utf8
    skip "missing String#encoding" unless "".respond_to?(:encoding)

    contents = File.read("test/fixtures/encoding/utf-8.txt")

    assert_equal(Encoding::UTF_8, contents.encoding)
    assert_equal("\u2705\n", contents)
  end
end
