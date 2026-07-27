///|
/// An EIP-155 chain id. Carried on the wire as a minimal `0x`-prefixed hex
/// quantity (e.g. mainnet is `"0x1"`).
pub struct ChainId {
  priv value : UInt64
} derive(Eq, Debug)

///|
/// Build a chain id from a raw numeric value.
pub fn ChainId::new(value : UInt64) -> ChainId {
  ChainId::{ value, }
}

///|
/// The underlying numeric chain id.
pub fn ChainId::to_uint64(self : ChainId) -> UInt64 {
  self.value
}

///|
/// Ethereum mainnet (`1`).
pub fn ChainId::mainnet() -> ChainId {
  ChainId::{ value: 1 }
}

///|
/// Sepolia testnet (`11155111`).
pub fn ChainId::sepolia() -> ChainId {
  ChainId::{ value: 11155111 }
}

///|
/// Holesky testnet (`17000`).
pub fn ChainId::holesky() -> ChainId {
  ChainId::{ value: 17000 }
}

///|
/// OP Mainnet (`10`).
pub fn ChainId::optimism() -> ChainId {
  ChainId::{ value: 10 }
}

///|
/// Arbitrum One (`42161`).
pub fn ChainId::arbitrum() -> ChainId {
  ChainId::{ value: 42161 }
}

///|
/// Polygon PoS mainnet (`137`).
pub fn ChainId::polygon() -> ChainId {
  ChainId::{ value: 137 }
}

///|
/// Base mainnet (`8453`).
pub fn ChainId::base() -> ChainId {
  ChainId::{ value: 8453 }
}

///|
/// Parse a `0x`-prefixed hex quantity into a chain id.
pub fn ChainId::from_hex(s : String) -> ChainId raise CodecError {
  ChainId::{ value: parse_quantity(s, what="chain id") }
}

///|
/// Encode as a minimal `0x`-prefixed hex quantity.
pub fn ChainId::to_hex(self : ChainId) -> String {
  format_quantity(self.value)
}

///|
/// Encode as a JSON hex-quantity string.
pub fn ChainId::to_json(self : ChainId) -> Json {
  Json::string(self.to_hex())
}

///|
/// Decode from a JSON hex-quantity string.
pub fn ChainId::from_json(j : Json) -> ChainId raise CodecError {
  match j {
    String(s) => ChainId::from_hex(s)
    _ => raise InvalidJson("expected chain id string")
  }
}

///|
pub impl Show for ChainId with fn output(self, logger) {
  logger.write_string("ChainId(\{self.value})")
}
