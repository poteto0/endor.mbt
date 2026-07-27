///|
const A_BLOCK_HASH : String = "0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5"

///|
test "block hash parses, lowercases and round-trips through json" {
  let h = @types.BlockHash::from_string(
    "0xB6DE5C3C1B70D24DE3EA4EB90A6C9F1F5EB1D0E6A5E3B3F1B7E0C0B9A8D7C6E5",
  )
  inspect(h.to_string(), content=A_BLOCK_HASH)
  inspect(h.to_json().stringify(), content="\"\{A_BLOCK_HASH}\"")
  inspect(@types.BlockHash::from_json(h.to_json()), content=A_BLOCK_HASH)
}

///|
/// Same 32-byte rule as `TxHash`, and the error names *this* type — the two
/// share a parser, so the message is the only thing telling them apart.
test "block hash rejects anything that is not 32 bytes" {
  try @types.BlockHash::from_string(A_BLOCK_HASH + "ab") catch {
    @types.CodecError::InvalidLength(msg) =>
      assert_true(msg.has_prefix("block hash must be 32 bytes"))
    e => fail("expected InvalidLength, but not \{e}")
  } noraise {
    _ => fail("expected an over-long hash to be rejected")
  }
}

///|
test "block hash rejects non-string json" {
  try @types.BlockHash::from_json(Json::number(1)) catch {
    @types.CodecError::InvalidJson(_) => ()
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a number to be rejected")
  }
}
