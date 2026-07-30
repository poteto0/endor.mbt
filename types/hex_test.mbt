///|
/// Hex normalizes to lowercase.
test "can normalize hex" {
  inspect(@types.Hex::from_string("0xAB01").to_string(), content="0xab01")
  inspect(@types.Hex::from_string("0xab01").to_string(), content="0xab01")
  inspect(@types.Hex::from_string("0x").to_string(), content="0x")
}

///|
/// Invalid when not prefixed with `0x`.
test "invalid if missing 0x prefix" {
  try @types.Hex::from_string("ab01") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when non-hex characters exist.
test "invalid if contains non hex character" {
  try @types.Hex::from_string("0x0g") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when the body has an odd number of hex digits.
test "invalid if odd length" {
  try @types.Hex::from_string("0x123") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A message is encoded as its UTF-8 bytes, which is what a wallet decodes back
/// to show the user — not the UTF-16 a MoonBit string is held as.
test "can create from a utf-8 string" {
  inspect(@types.Hex::from_utf8("").to_string(), content="0x")
  inspect(@types.Hex::from_utf8("hello").to_string(), content="0x68656c6c6f")
  inspect(
    @types.Hex::from_utf8("こんにちは").to_string(),
    content="0xe38193e38293e381abe381a1e381af",
  )
  // outside the BMP: one code point, four UTF-8 bytes
  inspect(@types.Hex::from_utf8("🔥").to_string(), content="0xf09f94a5")
  // a byte below 0x10 keeps its leading zero, so the digits stay in step with
  // the bytes they came from
  inspect(@types.Hex::from_utf8("a\nb").to_string(), content="0x610a62")
  inspect(@types.Hex::from_utf8("hello").byte_length(), content="5")
}

///|
test "can convert to json" {
  inspect(
    @types.Hex::from_string("0xAB01").to_json().stringify(),
    content="\"0xab01\"",
  )
}

///|
test "can create from json" {
  inspect(@types.Hex::from_json("0xAB01").to_string(), content="0xab01")
}

///|
test "error if not string json" {
  try @types.Hex::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug hex" {
  let hex = @types.Hex::from_string("0xAB01")
  inspect(hex.to_string(), content="0xab01")
}

///|
/// Byte length counts whole bytes, and empty is the `"0x"` an account with no
/// contract code answers with.
test "can measure hex length" {
  inspect(@types.Hex::from_string("0x").byte_length(), content="0")
  inspect(@types.Hex::from_string("0xab01").byte_length(), content="2")
  inspect(@types.Hex::from_string("0x").is_empty(), content="true")
  inspect(@types.Hex::from_string("0x00").is_empty(), content="false")
}

///|
/// `from_digits` is the shortcut past `Bytes` that `@abi.encode` takes: it must
/// land on exactly the value the same digits would have reached the long way,
/// and it must still refuse what `from_string` refuses.
test "can create from digits alone" {
  assert_eq(
    @types.Hex::from_digits("deadbeef"),
    @types.Hex::from_string("0xdeadbeef"),
  )
  assert_eq(@types.Hex::from_digits("DEADBEEF").to_string(), "0xdeadbeef")
  assert_eq(@types.Hex::from_digits("").to_string(), "0x")
  refuses("abc", "InvalidLength(hex byte string must have even length: 0xabc)")
  refuses("0g", "InvalidHex(0x0g)")
  // the `0x` belongs to `from_string`; digits here are digits and nothing else
  refuses("0xab", "InvalidHex(0x0xab)")
}

///|
/// `Hex::from_digits` for the cases that must not build a value.
fn refuses(digits : String, expected : String) -> Unit raise {
  try @types.Hex::from_digits(digits) catch {
    e => assert_eq("\{e}", expected)
  } noraise {
    h => fail("expected \{digits} to be refused, got \{h}")
  }
}

///|
/// Both directions over a payload far longer than one word: what a digest or an
/// `eth_getCode` answer is, rather than the four bytes the cases above use.
test "a large value survives the round trip" {
  let payload = Bytes::makei(10_000, i => (i * 7 % 256).to_byte())
  let h = @types.Hex::from_bytes(payload)
  assert_eq(h.byte_length(), 10_000)
  assert_eq(h.to_bytes(), payload)
  assert_eq(@types.Hex::from_digits(h.digits()), h)
}

///|
/// `Hex::concat` — the two halves' bytes in order, with the empty value the
/// identity on either side, since `0x` is the value that spells no bytes.
test "two hex values join into one" {
  let code = @types.Hex::from_string("0x6080")
  let args = @types.Hex::from_string("0xdeadbeef")
  let empty = @types.Hex::from_string("0x")
  assert_eq(code.concat(args), @types.Hex::from_string("0x6080deadbeef"))
  assert_eq(code.concat(empty), code)
  assert_eq(empty.concat(code), code)
  assert_eq(code.concat(args).byte_length(), 6)
}
