///|
/// Quantities encode to minimal hex, including at both ends of the range.
test "can convert to hex from uint64" {
  assert_eq(@types.Quantity::new(0).to_hex(), "0x0")
  assert_eq(@types.Quantity::new(255).to_hex(), "0xff")
  assert_eq(
    @types.Quantity::new(18446744073709551615).to_hex(),
    "0xffffffffffffffff",
  )
}

///|
/// Parse a hex quantity, leading zeros and uppercase digits included.
test "can convert from hex" {
  assert_eq(@types.Quantity::from_hex("0x0").to_uint64(), 0)
  assert_eq(@types.Quantity::from_hex("0x00ff").to_uint64(), 255)
  assert_eq(@types.Quantity::from_hex("0xFF").to_uint64(), 255)
  assert_eq(
    @types.Quantity::from_hex("0xffffffffffffffff").to_uint64(),
    18446744073709551615,
  )
}

///|
test "invalid hex on empty or unprefixed" {
  for s in ["0x", "", "ff"] {
    try @types.Quantity::from_hex(s) catch {
      InvalidHex(_) => ()
      e => fail("expected invalid hex, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  }
}

///|
test "invalid hex on non hex character" {
  try @types.Quantity::from_hex("0x1g") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// One past the 64-bit range is a length error, not a silent wrap.
test "invalid if value exceeds uint64" {
  try @types.Quantity::from_hex("0x10000000000000000") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json" {
  assert_eq(@types.Quantity::new(1207).to_json(), "0x4b7")
}

///|
test "can create from json" {
  assert_eq(@types.Quantity::from_json("0x4b7").to_uint64(), 1207)
}

///|
test "error if not string json" {
  try @types.Quantity::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug quantity" {
  assert_eq(@types.Quantity::new(123).to_string(), "Quantity(123)")
}
