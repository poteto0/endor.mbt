///|
/// Strip the `0x` prefix and return the (possibly empty) body, validating that
/// every character is a hex digit. Raises `InvalidHex` otherwise.
fn strip_0x(s : String) -> String raise CodecError {
  guard s.has_prefix("0x") else { raise InvalidHex(s) }
  let body = s[2:].to_owned()
  for c in body {
    guard c.is_ascii_hexdigit() else { raise InvalidHex(s) }
  }
  body
}

///|
/// Validate that `s` is a `0x`-prefixed hex string and return its lowercased
/// normal form (without further length constraints). Raises `InvalidHex`
/// otherwise. An empty body (`"0x"`) is allowed.
fn normalize_hex(s : String) -> String raise CodecError {
  "0x" + strip_0x(s).to_lower()
}

///|
/// Validate that `s` is a 32-byte hex value and return its normal form. Every
/// identifier Ethereum hashes into is this shape, so `TxHash` and `BlockHash`
/// share one parser and differ only in the `what` their errors name.
fn parse_hash32(s : String, what~ : String) -> String raise CodecError {
  let n = normalize_hex(s)
  guard n.length() == 66 else {
    raise InvalidLength("\{what} must be 32 bytes (64 hex digits): \{s}")
  }
  n
}

///|
/// A raw `0x`-prefixed byte string as carried by JSON-RPC (e.g. `data`,
/// signatures, transaction hashes). The body must have an even number of hex
/// digits so it maps to whole bytes.
pub struct Hex {
  priv inner : String
} derive(Eq, Debug)

///|
/// Parse and validate a `0x`-prefixed hex byte string (even length).
pub fn Hex::from_string(s : String) -> Hex raise CodecError {
  let n = normalize_hex(s)
  guard (n.length() - 2) % 2 == 0 else {
    raise InvalidLength("hex byte string must have even length: \{s}")
  }
  Hex::{ inner: n }
}

///|
/// The canonical `0x`-prefixed lowercase string form.
pub fn Hex::to_string(self : Hex) -> String {
  self.inner
}

///|
/// How many bytes the value holds.
pub fn Hex::byte_length(self : Hex) -> Int {
  (self.inner.length() - 2) / 2
}

///|
/// Whether the value holds no bytes at all (`"0x"`) — what `eth_getCode`
/// answers for an account that is not a contract.
pub fn Hex::is_empty(self : Hex) -> Bool {
  self.byte_length() == 0
}

///|
/// Encode as a JSON string.
pub fn Hex::to_json(self : Hex) -> Json {
  Json::string(self.inner)
}

///|
/// Decode from a JSON string.
pub fn Hex::from_json(j : Json) -> Hex raise CodecError {
  match j {
    String(s) => Hex::from_string(s)
    _ => raise InvalidJson("expected hex string")
  }
}

///|
pub impl Show for Hex with fn output(self, logger) {
  logger.write_string(self.inner)
}
