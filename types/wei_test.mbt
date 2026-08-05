///|
/// Wei can be built from small integers and encodes to minimal hex quantities.
test "can convert to hex from num" {
  inspect(@types.Wei::from_int(1).to_hex(), content="0x1")
  inspect(@types.Wei::from_int(0).to_hex(), content="0x0")
  inspect(@types.Wei::from_int(255).to_hex(), content="0xff")
  inspect(@types.Wei::zero().to_hex(), content="0x0")
  inspect(@types.Wei::from_bigint(255).to_hex(), content="0xff")
}

///|
test "can convert to bigint from hex" {
  inspect(@types.Wei::from_hex("0xff").to_bigint(), content="255")
  inspect(@types.Wei::from_hex("0x0").to_bigint(), content="0")
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
  inspect(
    @types.Wei::from_hex("0xff").to_json().stringify(),
    content="\"0xff\"",
  )
}

///|
test "can create from json" {
  inspect(@types.Wei::from_json("0xff").to_hex(), content="0xff")
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
  inspect(wei.to_string(), content="Wei(123)")
}

///|
/// The scale a token declares, applied to what somebody typed.
test "from_units reads a decimal amount at any scale" {
  inspect(
    @types.Wei::from_units("1.5", decimals=18).to_bigint(),
    content="1500000000000000000",
  )
  // the six decimals of USDC and every stablecoin like it
  inspect(
    @types.Wei::from_units("1.5", decimals=6).to_bigint(),
    content="1500000",
  )
  inspect(
    @types.Wei::from_units("1", decimals=6).to_bigint(),
    content="1000000",
  )
  inspect(
    @types.Wei::from_units("0.05", decimals=6).to_bigint(),
    content="50000",
  )
  // a bare fraction, and a bare point, are both numbers
  inspect(
    @types.Wei::from_units(".5", decimals=6).to_bigint(),
    content="500000",
  )
  inspect(
    @types.Wei::from_units("12.", decimals=6).to_bigint(),
    content="12000000",
  )
  // an unscaled token counts whole units
  inspect(@types.Wei::from_units("42", decimals=0).to_bigint(), content="42")
  // and the smallest unit there is
  inspect(
    @types.Wei::from_units("0.000000000000000001", decimals=18).to_bigint(),
    content="1",
  )
}

///|
/// Every way an amount is refused, and the one error all of them are: an amount
/// finer than the scale (the failure this API exists to make impossible —
/// digits quietly dropped), anything that is not a decimal number, and a scale
/// that is not one.
test "from_units refuses what it cannot hold" {
  let refused = []
  for
    case in [
      ("1.0000000000000000001", 18),
      ("1.5", 0),
      ("", 18),
      (".", 18),
      ("1.2.3", 18),
      ("-1", 18),
      ("1e18", 18),
      ("1,000", 18),
      ("0x10", 18),
      ("abc", 18),
      ("1", -1),
    ] {
    let (typed, decimals) = case
    try @types.Wei::from_units(typed, decimals~) |> ignore catch {
      InvalidDecimal(_) => refused.push(typed)
      e => fail("expected invalid decimal for \{typed}, but not \{e}")
    } noraise {
      _ => fail("expected \{typed} at \{decimals} decimals to be refused")
    }
  }
  assert_eq(refused.length(), 11)
}

///|
/// Reading a balance back: trailing zeros folded, and nothing else added.
test "to_units writes the amount back" {
  inspect(@types.Wei::from_int(1500000).to_units(decimals=6), content="1.5")
  inspect(@types.Wei::from_int(1000000).to_units(decimals=6), content="1")
  inspect(@types.Wei::from_int(1234560).to_units(decimals=6), content="1.23456")
  inspect(@types.Wei::from_int(1).to_units(decimals=6), content="0.000001")
  inspect(@types.Wei::zero().to_units(decimals=18), content="0")
  inspect(@types.Wei::from_int(42).to_units(decimals=0), content="42")
}

///|
/// The two scales the chain fixes, as the aliases that spell them.
test "ether and gwei are from_units with the scale filled in" {
  inspect(
    @types.Wei::from_ether("0.05").to_bigint(),
    content="50000000000000000",
  )
  inspect(@types.Wei::from_ether("0.05").to_ether(), content="0.05")
  inspect(@types.Wei::from_gwei("21.5").to_bigint(), content="21500000000")
  inspect(@types.Wei::from_gwei("21.5").to_gwei(), content="21.5")
  // one ether, read at each of the two scales
  let one = @types.Wei::from_ether("1")
  inspect(one.to_gwei(), content="1000000000")
  inspect(one.to_hex(), content="0xde0b6b3a7640000")
}

///|
/// What a dapp actually does: read a balance off the wire and show it, then
/// take back what the user typed.
test "a balance survives the round trip through what a human reads" {
  let balance = @types.Wei::from_hex("0x4563918244f40000")
  inspect(balance.to_ether(), content="5")
  assert_eq(@types.Wei::from_ether(balance.to_ether()), balance)
}
