///|
/// Render an encoding as hex, which is how every published RLP vector is
/// written down.
fn hex(item : @rlp.Item) -> String {
  @codec.digits_of_bytes(@rlp.encode(item))
}

///|
/// The strings from the RLP section of the yellow paper's appendix, as
/// `ethereum/tests` publishes them in `RLPTests/rlptest.json`.
test "strings encode with a length in front" {
  assert_eq(hex(Bytes(b"dog")), "83646f67")
  assert_eq(hex(Bytes(b"")), "80")
  // Below 0x80 a single byte is its own encoding, with no header at all.
  assert_eq(hex(Bytes(b"\x00")), "00")
  assert_eq(hex(Bytes(b"\x0f")), "0f")
  // At 0x80 the byte can no longer stand for itself, so it gets a header.
  assert_eq(hex(Bytes(b"\x80")), "8180")
  assert_eq(hex(Bytes(b"\x04\x00")), "820400")
}

///|
/// 55 bytes is the last length a single header byte can carry; 56 is the first
/// that has to write the length out. Both sides of that boundary, since it is
/// the one place the two forms meet.
test "the length prefix changes form at 55 bytes" {
  assert_eq(hex(Bytes(Bytes::make(55, b'a'))), "b7" + "61".repeat(55))
  assert_eq(hex(Bytes(Bytes::make(56, b'a'))), "b838" + "61".repeat(56))
  // Two bytes of length, once past what one can count to.
  assert_eq(hex(Bytes(Bytes::make(1024, b'a'))), "b90400" + "61".repeat(1024))
}

///|
test "lists encode their items run together" {
  assert_eq(hex(List([])), "c0")
  assert_eq(hex(List([Bytes(b"cat"), Bytes(b"dog")])), "c88363617483646f67")
}

///|
/// The yellow paper's "set theoretical representation of three": nesting is
/// the whole of what makes RLP recursive, and this is the vector that exercises
/// it without any bytes getting in the way.
test "lists nest" {
  assert_eq(
    hex(List([List([]), List([List([])]), List([List([]), List([List([])])])])),
    "c7c0c1c0c3c0c1c0",
  )
}

///|
/// A list long enough to need the second header form, which is what every real
/// transaction is.
test "a long list writes its length out" {
  let words = Array::make(4, @rlp.Item::Bytes(b"Lorem ipsum dolor sit amet"))
  // Four 26-byte strings with a one-byte header each: 108 bytes of payload.
  assert_eq(
    hex(List(words)),
    "f86c" +
    ("9a" + "4c6f72656d20697073756d20646f6c6f722073697420616d6574").repeat(4),
  )
}

///|
/// Numbers carry no leading zeros, so that one number has exactly one
/// encoding — the property a transaction hash rests on.
test "numbers are written in the fewest bytes" {
  assert_eq(hex(@rlp.Item::of_uint64(0)), "80")
  assert_eq(hex(@rlp.Item::of_uint64(15)), "0f")
  assert_eq(hex(@rlp.Item::of_uint64(1024)), "820400")
  assert_eq(hex(@rlp.Item::of_uint64(0xff)), "81ff")
  assert_eq(hex(@rlp.Item::of_uint64(0xffffffffffffffff)), "88ffffffffffffffff")
}

///|
/// The same rule above 64 bits, where a `Wei` amount and the halves of a
/// signature live.
test "wide numbers follow the same rule" {
  assert_eq(hex(@rlp.Item::of_bigint(0N)), "80")
  assert_eq(hex(@rlp.Item::of_bigint(1N)), "01")
  assert_eq(
    hex(
      @rlp.Item::of_bigint(
        @bigint.BigInt::from_string("0de0b6b3a7640000", radix=16),
      ),
    ),
    "880de0b6b3a7640000",
  )
  // A full 32-byte value keeps all of its bytes.
  assert_eq(
    hex(
      @rlp.Item::of_bigint(
        @bigint.BigInt::from_string(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          radix=16,
        ),
      ),
    ),
    "a0" + "ff".repeat(32),
  )
}
