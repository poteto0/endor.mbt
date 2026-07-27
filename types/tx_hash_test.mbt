///|
const A_HASH : String = "0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b"

///|
test "transaction hash parses, lowercases and round-trips through json" {
  let h = @types.TxHash::from_string(
    "0x88DF016429689C079F3B2F6AD39FA052532C56795B733DA78A91EBE6A713944B",
  )
  inspect(h.to_string(), content=A_HASH)
  inspect(h.to_json().stringify(), content="\"\{A_HASH}\"")
  inspect(@types.TxHash::from_json(h.to_json()), content=A_HASH)
  inspect(h, content=A_HASH)
}

///|
/// The whole point of the type: a value that is not 32 bytes is rejected here
/// rather than at whichever RPC is later handed it.
test "transaction hash rejects anything that is not 32 bytes" {
  for
    bad in [
      // 31 bytes
      "0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a7139",
      // 33 bytes
      A_HASH + "ab",
      // an address is a hash-shaped string of the wrong length
      "0x52908400098527886e0f7030069857d2e4169ee7",
      "0x",
    ] {
    try @types.TxHash::from_string(bad) catch {
      @types.CodecError::InvalidLength(_) => ()
      e => fail("expected InvalidLength, but not \{e}")
    } noraise {
      _ => fail("expected \{bad} to be rejected")
    }
  }
}

///|
test "transaction hash rejects non-hex and non-string json" {
  try
    @types.TxHash::from_string(
      "88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b",
    )
  catch {
    @types.CodecError::InvalidHex(_) => ()
    e => fail("expected InvalidHex, but not \{e}")
  } noraise {
    _ => fail("expected an unprefixed hash to be rejected")
  }
  try @types.TxHash::from_json(Json::number(1)) catch {
    @types.CodecError::InvalidJson(_) => ()
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a non-string to be rejected")
  }
}
