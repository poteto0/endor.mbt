///|
/// A 256-bit unsigned quantity of wei (smallest ETH unit), backed by `BigInt`.
/// Carried on the wire as a minimal `0x`-prefixed hex quantity.
///
/// ```
/// let w = @types.Wei::from_int(255)
/// inspect(w.to_hex(), content="0xff")
/// ```
pub struct Wei {
  priv value : BigInt
} derive(Eq, Debug)

///|
/// Build a wei amount from a small non-negative integer.
pub fn Wei::from_int(n : Int) -> Wei {
  Wei::{ value: BigInt::from_int(n) }
}

///|
/// Build a wei amount from a `BigInt`.
pub fn Wei::from_bigint(n : BigInt) -> Wei {
  Wei::{ value: n }
}

///|
/// The underlying `BigInt` value.
pub fn Wei::to_bigint(self : Wei) -> BigInt {
  self.value
}

///|
/// Zero wei.
pub fn Wei::zero() -> Wei {
  Wei::{ value: BigInt::from_int(0) }
}

///|
/// Parse a `0x`-prefixed hex quantity into a wei amount.
pub fn Wei::from_hex(s : String) -> Wei raise CodecError {
  let body = strip_0x(s)
  guard body.length() > 0 else { raise InvalidHex("empty wei quantity: \{s}") }
  Wei::{ value: BigInt::from_string(body, radix=16) }
}

///|
/// Encode as a minimal `0x`-prefixed hex quantity.
pub fn Wei::to_hex(self : Wei) -> String {
  "0x" + self.value.to_string(radix=16)
}

///|
/// Encode as a JSON hex-quantity string.
pub fn Wei::to_json(self : Wei) -> Json {
  Json::string(self.to_hex())
}

///|
/// Decode from a JSON hex-quantity string.
pub fn Wei::from_json(j : Json) -> Wei raise CodecError {
  match j {
    String(s) => Wei::from_hex(s)
    _ => raise InvalidJson("expected wei string")
  }
}

///|
pub impl Show for Wei with fn output(self, logger) {
  logger.write_string("Wei(\{self.value})")
}
