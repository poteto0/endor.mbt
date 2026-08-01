///|
/// The demo's only piece of money arithmetic, so it is the only piece with a
/// test: everything else here is wiring the SDK to the DOM.
test "ether amounts scale to wei" {
  let cases = [
    ("1", "1000000000000000000"),
    ("0.01", "10000000000000000"),
    (".5", "500000000000000000"),
    ("0", "0"),
    ("0.000000000000000001", "1"),
    // leading zeros and surrounding spaces are the shape a paste has
    ("  007.5 ", "7500000000000000000"),
  ]
  for c in cases {
    let (amount, wei) = c
    guard wei_of_ether(amount) is Some(got) else {
      fail("\{amount} should parse")
    }
    assert_eq(got.to_bigint().to_string(), wei)
  }
}

///|
/// What must not reach the wallet: anything that is not a plain decimal, and
/// any amount finer than a wei — rounding someone's money down is worse than
/// making them retype it.
test "amounts that are not decimals are rejected" {
  for
    bad in [
      "", " ", ".", "-1", "1e18", "0x1", "1.2.3", "1 000",
      // 19 decimals: finer than a wei
       "0.0000000000000000001",
    ] {
    inspect(wei_of_ether(bad) is None, content="true")
  }
}
