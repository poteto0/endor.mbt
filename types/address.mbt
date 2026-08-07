///|
/// Apply EIP-55 casing to the 40 lowercase hex digits of an address body (no
/// `0x` prefix).
///
/// The check code is keccak256 of those digits taken *as ASCII text* — not of
/// the 20 bytes they denote. Digit `i` is uppercased when the `i`-th hex digit
/// (nibble) of the hash is `>= 8`; the decimal digits, having no case, simply
/// stay as they are and carry no part of the check code.
fn eip55_body(lower_body : String) -> String {
  let hash = @crypto.keccak256_string(lower_body)
  let out = StringBuilder::new()
  for i, c in lower_body.iter2() {
    let byte = hash[i / 2].to_int()
    let nibble = if i % 2 == 0 { byte >> 4 } else { byte & 0x0f }
    out.write_char(if nibble >= 8 { c.to_ascii_uppercase() } else { c })
  }
  out.to_string()
}

///|
/// A 20-byte Ethereum address. Parsing validates the `0x` prefix, hex digits
/// and exact 20-byte length; the value is stored lowercased. EIP-55 checksum
/// casing is a later milestone.
pub struct Address {
  priv inner : String
} derive(Eq, Debug)

///|
/// Parse and validate a 20-byte hex address. Input that is entirely lowercase
/// or entirely uppercase carries no EIP-55 checksum and is accepted as-is;
/// mixed-case input claims to be checksummed, so it has to prove it.
pub fn Address::from_string(s : String) -> Address raise CodecError {
  let body = strip_0x(s)
  guard body.length() == 40 else {
    raise InvalidLength("address must be 20 bytes (40 hex digits): \{s}")
  }
  let lower = body.to_lower()
  guard body == lower || body == lower.to_upper() || body == eip55_body(lower) else {
    raise InvalidChecksum("address fails its EIP-55 checksum: \{s}")
  }
  Address::{ inner: "0x" + lower }
}

///|
/// The canonical `0x`-prefixed lowercase string form — what goes on the wire.
pub fn Address::to_string(self : Address) -> String {
  self.inner
}

///|
/// The 40 hex digits this address spells, without the `0x` — what a caller
/// working in digits packs into a word.
pub fn Address::digits(self : Address) -> String {
  self.inner[2:].to_owned()
}

///|
/// The EIP-55 checksummed spelling, for display to a human.
///
/// ```
/// let a = @types.Address::from_string("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
/// inspect(a.to_checksum_string(), content="0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
/// ```
pub fn Address::to_checksum_string(self : Address) -> String {
  "0x" + eip55_body(self.digits())
}

///|
/// Encode as a JSON string, in the lowercase wire form.
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
  json_array_of(j, what="address", Address::from_json)
}

///|
/// Displays the checksummed form; the wire form is `to_string` / `to_json`.
pub impl Show for Address with fn output(self, logger) {
  logger.write_string(self.to_checksum_string())
}
