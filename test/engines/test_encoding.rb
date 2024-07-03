require 'minitest/autorun'

class TestEncoding < Minitest::Test
  def test_utf8
    assert_equal("".encoding, Encoding::UTF_8)
  end

  def test_read_utf8
    contents = File.read('test/fixtures/encoding/utf-8.txt')
    assert_equal(contents.encoding, Encoding::UTF_8)
    assert_equal(contents, "\u2705\n")
  end
end
