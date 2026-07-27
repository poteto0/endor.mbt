///|
/// Parse the body of a `0x`-prefixed hex quantity into a `UInt64`. `what`
/// names the quantity in the error messages ("chain id", "block number", …),
/// so every caller reports its own domain rather than a generic one.
fn parse_quantity(s : String, what~ : String) -> UInt64 raise CodecError {
  let body = strip_0x(s)
  guard body.length() > 0 else { raise InvalidHex("empty \{what}: \{s}") }
  // `strip_0x` already rejected non-hex digits, so the only remaining failure
  // is a value too large for 64 bits.
  @string.parse_uint64(body, base=16) catch {
    _ => raise InvalidLength("\{what} exceeds 64 bits: \{s}")
  }
}

///|
/// Render a `UInt64` as the minimal `0x`-prefixed hex quantity the wire wants.
fn format_quantity(value : UInt64) -> String {
  "0x" + value.to_string(radix=16)
}

///|
/// A JSON-RPC quantity: an unsigned number carried on the wire as a minimal
/// `0x`-prefixed hex string. Block numbers, nonces and gas amounts all use this
/// encoding, so they all decode through this one type.
///
/// Values larger than 64 bits (only reachable for wei-denominated fields) are
/// out of range here; use `Wei` for those.
pub struct Quantity {
  priv value : UInt64
} derive(Eq, Debug)

///|
/// Build a quantity from a raw numeric value.
pub fn Quantity::new(value : UInt64) -> Quantity {
  Quantity::{ value, }
}

///|
/// The underlying numeric value.
pub fn Quantity::to_uint64(self : Quantity) -> UInt64 {
  self.value
}

///|
/// Parse a `0x`-prefixed hex quantity.
pub fn Quantity::from_hex(s : String) -> Quantity raise CodecError {
  Quantity::{ value: parse_quantity(s, what="quantity") }
}

///|
/// Encode as a minimal `0x`-prefixed hex quantity.
pub fn Quantity::to_hex(self : Quantity) -> String {
  format_quantity(self.value)
}

///|
/// Encode as a JSON hex-quantity string.
pub fn Quantity::to_json(self : Quantity) -> Json {
  Json::string(self.to_hex())
}

///|
/// Decode from a JSON hex-quantity string.
pub fn Quantity::from_json(j : Json) -> Quantity raise CodecError {
  match j {
    String(s) => Quantity::from_hex(s)
    _ => raise InvalidJson("expected quantity string")
  }
}

///|
pub impl Show for Quantity with fn output(self, logger) {
  logger.write_string("Quantity(\{self.value})")
}
