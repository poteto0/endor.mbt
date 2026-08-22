///|
/// Apply EIP-55 casing to the 40 lowercase hex digits of an address body (no
/// `0x` prefix).
///
/// The check code is keccak256 of those digits taken *as ASCII text* — not of
/// the 20 bytes they denote. Digit `i` is uppercased when the `i`-th hex digit
/// (nibble) of the hash is `>= 8`; the decimal digits, having no case, simply
/// stay as they are and carry no part of the check code.
fn eip55_body(lower_body : String) -> String {
  let hash = @keccak.keccak256_string(lower_body)
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
/// and exact 20-byte length; the value is stored lowercased — the wire form.
///
/// The EIP-55 spelling is a memo the first display fills: an address that is
/// only decoded, compared or sent back out never hashes. It is not part of the
/// value, so `Eq` and `Debug` are hand-written to read `inner` alone.
pub struct Address {
  priv inner : String
  priv mut eip55 : String?
}

///|
/// Two addresses are the same address when they spell the same digits; the
/// checksum memo is a rendering, not a difference.
pub impl Eq for Address with fn equal(self, other) {
  self.inner == other.inner
}

///|
/// Debugs as the wire form, so the output does not depend on whether the
/// checksum has been asked for yet.
pub impl @debug.Debug for Address with fn to_repr(self) {
  @debug.Repr::Repr(self.inner)
}

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
  if body == lower || body == lower.to_upper() {
    return Address::of_lower_digits(lower)
  }
  // Mixed case claims a checksum: the spelling that proves it is the memo.
  let cased = eip55_body(lower)
  guard body == cased else {
    raise InvalidChecksum("address fails its EIP-55 checksum: \{s}")
  }
  { inner: "0x" + lower, eip55: Some("0x" + cased) }
}

///|
/// Build an address out of 40 lowercase hex digits already known to be 40
/// lowercase hex digits — no `0x` to strip, nothing to validate, no checksum
/// to prove. The prefix the type carries is put on here, so nothing else has
/// to know it is stored prefixed.
fn Address::of_lower_digits(lower : String) -> Address {
  { inner: "0x" + lower, eip55: None }
}

///|
/// The address a secp256k1 public key derives: the last 20 bytes of the
/// Keccak-256 of its two coordinates.
///
/// Takes the uncompressed SEC1 form — the `0x04` tag byte followed by the 64
/// bytes of `x` and `y`, which is what `@secp256k1.PrivateKey::public_key`
/// hands back. The tag is what says the coordinates are there in full, so it
/// is checked and then hashed over, exactly as Ethereum defines the
/// derivation.
///
/// It lives here rather than beside the curve because `Address` is this
/// package's type and the layers only point one way: `crypto/secp256k1` knows
/// nothing about addresses.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let address = @types.Address::from_public_key(key.public_key())
/// inspect(address.to_string(), content="0x970e8128ab834e8eac17ab8e3812f010678cf791")
/// ```
pub fn Address::from_public_key(public_key : Bytes) -> Address raise CodecError {
  guard public_key.length() == 65 && public_key[0] == b'\x04' else {
    raise InvalidLength(
      "public key must be 65 uncompressed bytes tagged 0x04: \{public_key.length()} bytes",
    )
  }
  address_of_tagged_key(public_key)
}

///|
/// The address a public key already known to be a point derives: drop the
/// `0x04` tag, Keccak-256 the 64 coordinate bytes, keep the last 20.
///
/// Built rather than parsed: the input is established — by `from_public_key`
/// off the wire, by the curve itself in `Address::recover` — and the digits
/// come out of a hash, so there is no form to check and no checksum casing to
/// prove. Nothing here can raise.
fn address_of_tagged_key(public_key : Bytes) -> Address {
  let hash = @keccak.keccak256(public_key[1:].to_owned())
  Address::of_lower_digits(@codec.digits_of_bytes(hash[12:].to_owned()))
}

///|
/// The address that signed `digest`: ecrecover, ending where Ethereum ends it.
///
/// `@secp256k1.Signature::recover` does the curve work and answers with the
/// public key, because the curve package sits below this one and knows no
/// `Address`. This is the same call with the derivation on the end, and it is
/// the one to reach for: an address is what a contract, a log or a transaction
/// names a signer by.
///
/// It raises `@secp256k1.CurveError` and nothing else. The bytes it derives
/// from come out of the curve rather than off a wire, so there is no address
/// to validate and no `CodecError` to raise — which is why the derivation
/// above is a separate, infallible step.
///
/// Recovery is not verification: it answers with whichever address would have
/// signed this digest, so a caller checking a signature compares the answer
/// with the address it expected.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let digest = @keccak.keccak256(b"foo")
/// let signer = @types.Address::recover(digest, key.sign(digest))
/// inspect(signer.to_string(), content="0x970e8128ab834e8eac17ab8e3812f010678cf791")
/// ```
pub fn Address::recover(
  digest : Bytes,
  signature : @secp256k1.Signature,
) -> Address raise @secp256k1.CurveError {
  address_of_tagged_key(signature.recover(digest))
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
/// The EIP-55 checksummed spelling, for display to a human. Costs one
/// `keccak256` the first time it is asked for, and nothing after.
///
/// ```
/// let a = @types.Address::from_string("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
/// inspect(a.to_checksum_string(), content="0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
/// ```
pub fn Address::to_checksum_string(self : Address) -> String {
  match self.eip55 {
    Some(cached) => cached
    None => {
      let cased = "0x" + eip55_body(self.digits())
      self.eip55 = Some(cased)
      cased
    }
  }
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
