///|
/// Address normalizes to lowercase.
test "can normalize address" {
  assert_eq(
    @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7").to_string(),
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
/// Invalid when not prefixed with `0x`.
test "invalid if missing 0x prefix" {
  try
    @types.Address::from_string("52908400098527886e0f7030069857d2e4169ee7")
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when non-hex characters exist.
test "invalid if contains non hex character" {
  try
    @types.Address::from_string("0x52908400098527886e0f7030069857d2e4169eeG")
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when the address is not exactly 20 bytes.
test "invalid if wrong length" {
  try @types.Address::from_string("0x1234") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  try
    @types.Address::from_string("0x52908400098527886e0f7030069857d2e4169ee700")
  catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json" {
  let address = @types.Address::from_string(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  assert_eq(address.to_json(), "0x52908400098527886e0f7030069857d2e4169ee7")
}

///|
test "can create from json" {
  let address = @types.Address::from_json(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  assert_eq(address.to_string(), "0x52908400098527886e0f7030069857d2e4169ee7")
}

///|
test "error if not string json" {
  try @types.Address::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug address" {
  let address = @types.Address::from_string(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  assert_eq(address.to_string(), "0x52908400098527886e0f7030069857d2e4169ee7")
}

///|
/// The account-listing RPCs answer with an array of address strings.
test "can create many from json" {
  let addresses = @types.Address::array_from_json([
    "0x52908400098527886E0F7030069857D2E4169EE7", "0x52908400098527886E0F7030069857D2E4169EE8",
  ])
  assert_eq(addresses.length(), 2)
  assert_eq(
    addresses[0].to_string(),
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  assert_eq(@types.Address::array_from_json(Json::array([])).length(), 0)
}

///|
test "error if not an array of addresses" {
  // not an array at all
  try @types.Address::array_from_json("0x1234") catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  // an array holding something that is not an address
  try
    @types.Address::array_from_json(Json::array(["invalid".to_json()]))
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
