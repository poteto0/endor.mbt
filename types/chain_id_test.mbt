///|
/// ChainId can be built from numbers and encodes to minimal hex quantities.
test "can convert to hex from uint64" {
  assert_eq(@types.ChainId::new(1).to_hex(), "0x1")
  assert_eq(@types.ChainId::new(0).to_hex(), "0x0")
  assert_eq(@types.ChainId::new(255).to_hex(), "0xff")
}

///|
/// Parse a hex quantity into a chain id.
test "can convert from hex" {
  assert_eq(@types.ChainId::from_hex("0x1").to_uint64(), 1)
  assert_eq(@types.ChainId::from_hex("0x0").to_uint64(), 0)
  assert_eq(@types.ChainId::from_hex("0xff").to_uint64(), 255)
}

///|
/// Common chain ids.
test "common chain ids" {
  assert_eq(@types.ChainId::mainnet().to_uint64(), 1)
  assert_eq(@types.ChainId::sepolia().to_uint64(), 11155111)
  assert_eq(@types.ChainId::holesky().to_uint64(), 17000)
  assert_eq(@types.ChainId::optimism().to_uint64(), 10)
  assert_eq(@types.ChainId::arbitrum().to_uint64(), 42161)
  assert_eq(@types.ChainId::polygon().to_uint64(), 137)
  assert_eq(@types.ChainId::amoy().to_uint64(), 80002)
  assert_eq(@types.ChainId::base().to_uint64(), 8453)
}

///|
test "invalid hex on empty" {
  try @types.ChainId::from_hex("0x") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  try @types.ChainId::from_hex("") catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "invalid if value exceeds uint64" {
  try @types.ChainId::from_hex("0x10000000000000000") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json" {
  assert_eq(@types.ChainId::new(8453).to_json(), "0x2105")
}

///|
test "can create from json" {
  assert_eq(@types.ChainId::from_json("0x2105").to_uint64(), 8453)
}

///|
test "error if not string json" {
  try @types.ChainId::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug chain id" {
  let chain_id = @types.ChainId::new(123)
  assert_eq(chain_id.to_string(), "ChainId(123)")
}
