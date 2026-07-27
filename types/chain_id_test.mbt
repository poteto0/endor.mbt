///|
/// ChainId can be built from numbers and encodes to minimal hex quantities.
test "can convert to hex from uint64" {
  inspect(@types.ChainId::new(1).to_hex(), content="0x1")
  inspect(@types.ChainId::new(0).to_hex(), content="0x0")
  inspect(@types.ChainId::new(255).to_hex(), content="0xff")
}

///|
/// Parse a hex quantity into a chain id.
test "can convert from hex" {
  inspect(@types.ChainId::from_hex("0x1").to_uint64(), content="1")
  inspect(@types.ChainId::from_hex("0x0").to_uint64(), content="0")
  inspect(@types.ChainId::from_hex("0xff").to_uint64(), content="255")
}

///|
/// Common chain ids.
test "common chain ids" {
  inspect(@types.ChainId::mainnet().to_uint64(), content="1")
  inspect(@types.ChainId::sepolia().to_uint64(), content="11155111")
  inspect(@types.ChainId::holesky().to_uint64(), content="17000")
  inspect(@types.ChainId::optimism().to_uint64(), content="10")
  inspect(@types.ChainId::arbitrum().to_uint64(), content="42161")
  inspect(@types.ChainId::polygon().to_uint64(), content="137")
  inspect(@types.ChainId::amoy().to_uint64(), content="80002")
  inspect(@types.ChainId::base().to_uint64(), content="8453")
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
  inspect(@types.ChainId::new(8453).to_json().stringify(), content="\"0x2105\"")
}

///|
test "can create from json" {
  inspect(@types.ChainId::from_json("0x2105").to_uint64(), content="8453")
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
  inspect(chain_id.to_string(), content="ChainId(123)")
}
