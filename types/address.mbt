///|
/// A 20-byte Ethereum address. Parsing validates the `0x` prefix, hex digits
/// and exact 20-byte length; the value is stored lowercased. EIP-55 checksum
/// casing is a later milestone.
pub struct Address {
  priv inner : String
} derive(Eq, Debug)

///|
/// Parse and validate a 20-byte hex address.
pub fn Address::from_string(s : String) -> Address raise CodecError {
  let n = normalize_hex(s)
  guard n.length() == 42 else {
    raise InvalidLength("address must be 20 bytes (40 hex digits): \{s}")
  }
  Address::{ inner: n }
}

///|
/// The canonical `0x`-prefixed lowercase string form.
pub fn Address::to_string(self : Address) -> String {
  self.inner
}

///|
/// Encode as a JSON string.
pub fn Address::to_json(self : Address) -> Json {
  Json::string(self.inner)
}

///|
/// Decode from a JSON string.
pub fn Address::from_json(j : Json) -> Address raise CodecError {
  match j {
    String(s) => Address::from_string(s)
    _ => raise InvalidJson("expected address string")
  }
}

///|
/// Decode a JSON array of address strings, as the account-listing RPCs
/// (`eth_accounts`, `eth_requestAccounts`) answer with.
pub fn Address::array_from_json(j : Json) -> Array[Address] raise CodecError {
  guard j is Array(items) else {
    raise InvalidJson("expected an array of addresses")
  }
  let out = []
  for it in items {
    out.push(Address::from_json(it))
  }
  out
}

///|
pub impl Show for Address with fn output(self, logger) {
  logger.write_string(self.inner)
}
