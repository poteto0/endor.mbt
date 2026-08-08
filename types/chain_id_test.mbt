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
/// The CAIP-2 spelling, against the constants for the same chains.
test "caip-2 round trip" {
  inspect(@types.ChainId::mainnet().to_caip2(), content="eip155:1")
  inspect(@types.ChainId::base().to_caip2(), content="eip155:8453")
  inspect(@types.ChainId::sepolia().to_caip2(), content="eip155:11155111")
  for
    chain in [
      @types.ChainId::mainnet(),
      @types.ChainId::sepolia(),
      @types.ChainId::holesky(),
      @types.ChainId::optimism(),
      @types.ChainId::arbitrum(),
      @types.ChainId::polygon(),
      @types.ChainId::amoy(),
      @types.ChainId::base(),
      // Base Sepolia, the chain the x402 examples are written against
      @types.ChainId::new(84532),
      @types.ChainId::new(0),
    ] {
    assert_eq(@types.ChainId::from_caip2(chain.to_caip2()), chain)
  }
}

///|
/// Another namespace is well-formed CAIP-2 naming a chain this type cannot
/// hold, so it is rejected on its namespace and not on its digits.
test "caip-2 rejects other namespaces" {
  for
    s in [
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", "bip122:000000000019d6", "eip1550:1",
      "EIP155:1", "8453", "eip155",
    ] {
    try @types.ChainId::from_caip2(s) catch {
      InvalidValue(_) => ()
      e => fail("expected invalid value for \{s}, but not \{e}")
    } noraise {
      _ => fail("expected fail for \{s}, but success")
    }
  }
}

///|
/// The reference is a decimal number, written the one way `to_caip2` writes it.
test "caip-2 rejects a non-canonical reference" {
  for
    s in [
      "eip155:", "eip155:0x1", "eip155:+1", "eip155:-1", "eip155:007", "eip155:1_0",
      "eip155:1 ", "eip155:１",
    ] {
    try @types.ChainId::from_caip2(s) catch {
      InvalidValue(_) => ()
      e => fail("expected invalid value for \{s}, but not \{e}")
    } noraise {
      _ => fail("expected fail for \{s}, but success")
    }
  }
}

///|
test "caip-2 rejects a reference beyond uint64" {
  try @types.ChainId::from_caip2("eip155:18446744073709551616") catch {
    InvalidValue(_) => ()
    e => fail("expected invalid value, but not \{e}")
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
