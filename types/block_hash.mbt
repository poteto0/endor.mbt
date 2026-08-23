///|
/// A 32-byte block hash: what a block and every receipt mined into it are
/// identified by, and what `eth_getBlockByHash` is asked with.
///
/// Deliberately not the same type as `TxHash`: handing one to an RPC expecting
/// the other is a mistake worth catching at compile time.
///
/// ```mbt check
/// test "doc: block hash" {
///   let h = @types.BlockHash::from_string(
///     "0xB6DE5C3C1B70D24DE3EA4EB90A6C9F1F5EB1D0E6A5E3B3F1B7E0C0B9A8D7C6E5",
///   )
///   inspect(
///     h.to_string(),
///     content="0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5",
///   )
/// }
/// ```
pub struct BlockHash {
  priv inner : String
} derive(Eq, Debug)

///|
/// Parse and validate a 32-byte hex block hash.
pub fn BlockHash::from_string(s : String) -> BlockHash raise CodecError {
  BlockHash::{ inner: parse_hash32(s, what="block hash") }
}

///|
/// The canonical `0x`-prefixed lowercase string form.
pub fn BlockHash::to_string(self : BlockHash) -> String {
  self.inner
}

///|
/// Encode as a JSON string.
pub fn BlockHash::to_json(self : BlockHash) -> Json {
  Json::string(self.inner)
}

///|
/// Decode from a JSON string.
pub fn BlockHash::from_json(j : Json) -> BlockHash raise CodecError {
  match j {
    String(s) => BlockHash::from_string(s)
    _ => raise InvalidJson("expected block hash string")
  }
}

///|
pub impl Show for BlockHash with fn output(self, logger) {
  logger.write_string(self.inner)
}
