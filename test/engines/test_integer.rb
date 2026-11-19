# ruby-version-min: 1.8.7

require "minitest/autorun"

class TestInteger < Minitest::Test
  def test_power_promotes_to_bignum
    assert_equal(1267650600228229401496703205376, 2 ** 100)
  end

  def test_multiplication_promotes_to_bignum
    assert_equal(18446744073709551616, 4294967296 * 4294967296)
    assert_equal(-18446744073709551616, -4294967296 * 4294967296)
  end
end
