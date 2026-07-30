///|
/// Two's complement both ways, at the one width the wire uses.
test "a word's bits read as signed and back" {
  let max_uint256 = (1N << 256) - 1N
  assert_eq(@codec.word_to_signed(max_uint256), -1N)
  assert_eq(@codec.word_to_unsigned(-1N), max_uint256)
  assert_eq(@codec.word_to_signed(1N), 1N)
  assert_eq(@codec.word_to_unsigned(1N), 1N)
  // the top bit is the sign, so half the range reads back negative
  assert_eq(@codec.word_to_signed(1N << 255), -(1N << 255))
  assert_eq(@codec.word_to_signed((1N << 255) - 1N), (1N << 255) - 1N)
}
