///|
/// Wei can be built from small integers and encodes to minimal hex quantities.
test "can convert to hex from num" {
  assert_eq(@types.Wei::from_int(1).to_hex(), "0x1")
  assert_eq(@types.Wei::from_int(0).to_hex(), "0x0")
  assert_eq(@types.Wei::from_int(255).to_hex(), "0xff")
  assert_eq(@types.Wei::zero().to_hex(), "0x0")
  assert_eq(@types.Wei::from_bigint(255).to_hex(), "0xff")
}

///|
test "can convert to bigint from hex" {
  assert_eq(@types.Wei::from_hex("0xff").to_bigint(), 255)
  assert_eq(@types.Wei::from_hex("0x0").to_bigint(), 0)
}

///|
test "can invalid hex on empty" {
  try @types.Wei::from_hex("0x") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  try @types.Wei::from_hex("") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json hex" {
  assert_eq(@types.Wei::from_hex("0xff").to_json(), "0xff")
}

///|
test "can create from json" {
  assert_eq(@types.Wei::from_json("0xff").to_hex(), "0xff")
}

///|
test "error if not string json" {
  try @types.Wei::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug Wei(value)" {
  let wei = @types.Wei::from_int(123)
  assert_eq(wei.to_string(), "Wei(123)")
}
