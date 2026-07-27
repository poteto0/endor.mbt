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

///|
/// The test vectors listed in EIP-55 itself: the checksummed spelling must be
/// what the lowercase form renders back to.
test "eip-55 test vectors round-trip" {
  let vectors = [
    // all caps
    "0x52908400098527886E0F7030069857D2E4169EE7", "0x8617E340B3D01FA5F11F306F4090FD50E238070D",
    // all lower
     "0xde709f2102306220921060314715629080e2fb77", "0x27b1fdb04752bbc536007a920d24acb045561c26",
    // normal
     "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
    "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB", "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
  ]
  for v in vectors {
    // parsing the checksummed form is accepted, and either uniform casing —
    // which carries no checksum at all — produces exactly that spelling back
    assert_eq(@types.Address::from_string(v).to_checksum_string(), v)
    assert_eq(@types.Address::from_string(v.to_lower()).to_checksum_string(), v)
    let upper = "0x" + v[2:].to_owned().to_upper()
    assert_eq(@types.Address::from_string(upper).to_checksum_string(), v)
  }
}

///|
/// Casing carries no information on the wire: all forms store and serialize
/// lowercase, while `Show` is the display form.
test "wire form stays lowercase, display is checksummed" {
  let a = @types.Address::from_string(
    "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
  )
  assert_eq(a.to_string(), "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
  assert_eq(a.to_json(), "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
  inspect(a, content="0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
}

///|
/// Mixed case claims a checksum, so a single flipped letter must be rejected.
test "invalid if mixed-case checksum does not match" {
  // `5aAeb…` with the leading `a` of the checksummed form uppercased
  try
    @types.Address::from_string("0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
  catch {
    InvalidChecksum(_) => ()
    e => fail("expected invalid checksum, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
