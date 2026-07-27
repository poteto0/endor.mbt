///|
/// Named tags travel as their bare names, numbers as hex quantities.
test "can convert to wire form" {
  inspect(@types.BlockTag::Latest.to_string(), content="latest")
  inspect(@types.BlockTag::Pending.to_string(), content="pending")
  inspect(@types.BlockTag::Earliest.to_string(), content="earliest")
  inspect(@types.BlockTag::Safe.to_string(), content="safe")
  inspect(@types.BlockTag::Finalized.to_string(), content="finalized")
  inspect(@types.BlockTag::Number(0).to_string(), content="0x0")
  inspect(@types.BlockTag::Number(16).to_string(), content="0x10")
}

///|
/// Every wire form parses back to the tag it came from.
test "can round trip through wire form" {
  let tags = [
    @types.BlockTag::Latest,
    Pending,
    Earliest,
    Safe,
    Finalized,
    Number(0),
    Number(18446744073709551615),
  ]
  for tag in tags {
    assert_eq(@types.BlockTag::from_string(tag.to_string()), tag)
  }
}

///|
/// Anything that is not a known tag is read as a block number, so a
/// misspelled tag fails as bad hex rather than silently meaning `latest`.
test "invalid hex on unknown tag" {
  for s in ["lastest", "0x", "16", "0x1g"] {
    try @types.BlockTag::from_string(s) catch {
      InvalidHex(_) => ()
      e => fail("expected invalid hex, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  }
}

///|
test "invalid if block number exceeds uint64" {
  try @types.BlockTag::from_string("0x10000000000000000") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json" {
  inspect(@types.BlockTag::Latest.to_json().stringify(), content="\"latest\"")
  inspect(@types.BlockTag::Number(16).to_json().stringify(), content="\"0x10\"")
}

///|
test "can create from json" {
  inspect(@types.BlockTag::from_json("pending"), content="pending")
  inspect(@types.BlockTag::from_json("0x10"), content="0x10")
}

///|
test "error if not string json" {
  try @types.BlockTag::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "show block tag" {
  inspect("\{@types.BlockTag::Number(16)}", content="0x10")
  inspect("\{@types.BlockTag::Safe}", content="safe")
}
