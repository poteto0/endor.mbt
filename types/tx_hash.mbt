///|
/// A 32-byte transaction hash — what `eth_sendTransaction` answers with, and
/// the handle every later question about the transaction (its receipt, its
/// confirmations) is asked with.
///
/// It is a `Hex` narrowed to exactly 32 bytes: a wallet answering with a
/// truncated or over-long value is a broken answer, and parsing here is where
/// that is caught rather than at the RPC that is later handed the value.
///
/// ```
/// let h = @types.TxHash::from_string(
///   "0x88DF016429689C079F3B2F6AD39FA052532C56795B733DA78A91EBE6A713944B",
/// )
/// inspect(
///   h.to_string(),
///   content="0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b",
/// )
/// ```
pub struct TxHash {
  priv inner : String
} derive(Eq, Debug)

///|
/// Parse and validate a 32-byte hex transaction hash.
pub fn TxHash::from_string(s : String) -> TxHash raise CodecError {
  TxHash::{ inner: parse_hash32(s, what="transaction hash") }
}

///|
/// The canonical `0x`-prefixed lowercase string form.
pub fn TxHash::to_string(self : TxHash) -> String {
  self.inner
}

///|
/// Encode as a JSON string.
pub fn TxHash::to_json(self : TxHash) -> Json {
  Json::string(self.inner)
}

///|
/// Decode from a JSON string.
pub fn TxHash::from_json(j : Json) -> TxHash raise CodecError {
  match j {
    String(s) => TxHash::from_string(s)
    _ => raise InvalidJson("expected transaction hash string")
  }
}

///|
pub impl Show for TxHash with fn output(self, logger) {
  logger.write_string(self.inner)
}
