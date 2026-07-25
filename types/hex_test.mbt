///|
/// Hex normalizes to lowercase.
test "can normalize hex" {
  assert_eq(@types.Hex::from_string("0xAB01").to_string(), "0xab01")
  assert_eq(@types.Hex::from_string("0xab01").to_string(), "0xab01")
  assert_eq(@types.Hex::from_string("0x").to_string(), "0x")
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
test "can convert to json" {
  assert_eq(@types.Hex::from_string("0xAB01").to_json(), "0xab01")
}

///|
test "can create from json" {
  assert_eq(@types.Hex::from_json("0xAB01").to_string(), "0xab01")
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
  assert_eq(hex.to_string(), "0xab01")
}

///|
/// Byte length counts whole bytes, and empty is the `"0x"` an account with no
/// contract code answers with.
test "can measure hex length" {
  assert_eq(@types.Hex::from_string("0x").byte_length(), 0)
  assert_eq(@types.Hex::from_string("0xab01").byte_length(), 2)
  assert_true(@types.Hex::from_string("0x").is_empty())
  assert_false(@types.Hex::from_string("0x00").is_empty())
}
