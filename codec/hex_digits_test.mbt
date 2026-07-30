///|
/// Digits and bytes, both ways — the conversion `@types.Hex` and `@abi` share.
test "bytes and the digits that spell them" {
  inspect(@codec.digits_of_bytes(b"\xde\xad\xbe\xef"), content="deadbeef")
  inspect(@codec.digits_of_bytes(b""), content="")
  assert_eq(@codec.bytes_of_digits("deadbeef"), b"\xde\xad\xbe\xef")
  assert_eq(@codec.bytes_of_digits(""), b"")
  // uppercase reads back the same, since a nibble is a nibble
  assert_eq(@codec.bytes_of_digits("DEADbeef"), b"\xde\xad\xbe\xef")
}

///|
/// What a `0x`-prefixed value's body is, which is the question every hex parser
/// above this package asks before raising its own error.
test "hex_body accepts only 0x and hex digits" {
  assert_eq(@codec.hex_body("0xab01"), Some("ab01"))
  assert_eq(@codec.hex_body("0x"), Some(""))
  assert_eq(@codec.hex_body("ab01"), None)
  assert_eq(@codec.hex_body("0x0g"), None)
  assert_eq(@codec.hex_body(""), None)
}

///|
/// The word rules as predicates: the one statement each layer asks.
test "the ABI's width and size rules" {
  assert_true(@codec.is_valid_bits(8))
  assert_true(@codec.is_valid_bits(256))
  assert_false(@codec.is_valid_bits(0))
  assert_false(@codec.is_valid_bits(7))
  assert_false(@codec.is_valid_bits(264))
  assert_true(@codec.is_valid_bytes_size(1))
  assert_true(@codec.is_valid_bytes_size(32))
  assert_false(@codec.is_valid_bytes_size(0))
  assert_false(@codec.is_valid_bytes_size(33))
  assert_true(@codec.is_valid_array_size(0))
  assert_false(@codec.is_valid_array_size(-1))
  assert_true(@codec.fits_uint(255N, bits=8))
  assert_false(@codec.fits_uint(256N, bits=8))
  assert_false(@codec.fits_uint(-1N, bits=8))
  assert_true(@codec.fits_int(127N, bits=8))
  assert_true(@codec.fits_int(-128N, bits=8))
  assert_false(@codec.fits_int(128N, bits=8))
  assert_false(@codec.fits_int(-129N, bits=8))
}

///|
/// Padding, in both units: `abi` slices digits, EIP-712 hashes bytes.
test "a value is padded into whole words" {
  inspect(
    @codec.digits_left_pad("ab"),
    content="00000000000000000000000000000000000000000000000000000000000000ab",
  )
  inspect(@codec.digits_right_pad("ab").length(), content="64")
  inspect(
    @codec.digits_right_pad(@codec.digits_left_pad("ab")).length(),
    content="64",
  )
  // a byte string longer than one word pads out to the next whole word
  inspect(@codec.digits_right_pad("ab".repeat(40)).length(), content="128")
  assert_eq(@codec.word_left_pad(b"\xab").length(), 32)
  assert_eq(@codec.word_left_pad(b"\xab")[31], b'\xab')
  assert_eq(@codec.word_right_pad(b"\xab")[0], b'\xab')
  assert_eq(
    @codec.concat_words([b"\x00".repeat(32), b"\x11".repeat(32)]).length(),
    64,
  )
}
