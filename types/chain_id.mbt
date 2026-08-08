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
/// Polygon Amoy testnet (`80002`) — the PoS testnet that replaced Mumbai.
pub fn ChainId::amoy() -> ChainId {
  ChainId::{ value: 80002 }
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
/// Parse a [CAIP-2](https://chainagnostic.org/CAIPs/caip-2) chain identifier —
/// `"eip155:8453"`, the spelling x402 writes its `network` field in.
///
/// Which chain family a CAIP-2 string names is not inferred from the number:
/// the namespace is written out in front of it, so this accepts `eip155:` and
/// nothing else. A well-formed identifier in another namespace (`solana:…`) is
/// `InvalidValue` — the form is fine, it just names a chain this type cannot
/// hold — and so is a reference that is not a plain decimal number.
///
/// The reference must be spelled the one way `to_caip2` spells it, which is
/// checked by comparing against that spelling: `@string.parse_uint64` on its
/// own also reads `"007"` and `"+7"` as 7, and accepting those would make the
/// round trip a thing that only usually holds.
///
/// This is the second of `ChainId`'s two wire spellings: `from_hex` / `to_hex`
/// are the `0x`-prefixed quantity JSON-RPC carries (`eth_chainId`),
/// `from_caip2` / `to_caip2` the CAIP-2 string.
///
/// ```mbt check
/// test "doc: chain id from caip-2" {
///   let id = @types.ChainId::from_caip2("eip155:8453")
///   assert_eq(id, @types.ChainId::base())
/// }
/// ```
pub fn ChainId::from_caip2(s : String) -> ChainId raise CodecError {
  guard s.has_prefix("eip155:") else {
    raise InvalidValue("not an eip155 chain id: \{s}")
  }
  let value = @string.parse_uint64(s[7:]) catch {
    _ => raise InvalidValue("chain id reference is not a uint64 decimal: \{s}")
  }
  guard s == "eip155:\{value}" else {
    raise InvalidValue("chain id reference is not canonical decimal: \{s}")
  }
  ChainId::{ value, }
}

///|
/// Encode as a CAIP-2 chain identifier (`"eip155:8453"`). The namespace is a
/// constant here: a `ChainId` is an EIP-155 chain id and names no other family.
///
/// ```mbt check
/// test "doc: chain id to caip-2" {
///   inspect(@types.ChainId::base().to_caip2(), content="eip155:8453")
/// }
/// ```
pub fn ChainId::to_caip2(self : ChainId) -> String {
  "eip155:\{self.value}"
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
