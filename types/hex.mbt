///|
/// Strip the `0x` prefix and return the (possibly empty) body, validating that
/// every character is a hex digit. Raises `InvalidHex` otherwise.
fn strip_0x(s : String) -> String raise CodecError {
  guard @codec.hex_body(s) is Some(body) else { raise InvalidHex(s) }
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
  guard s.has_prefix("0x") else { raise InvalidHex(s) }
  Hex::from_digits(s[2:])
}

///|
/// Build a hex byte string from the digits alone, with no `0x` and no bytes in
/// between — what a caller that already computed the digits wants, since
/// spelling them as `Bytes` only to have them spelled back costs two passes and
/// two copies over the whole value. ABI calldata is built this way.
///
/// This is where both of `Hex`'s rules are stated: `from_string` is this with
/// the prefix taken off first. A shortcut past the representation is not a
/// shortcut past the rule.
///
/// ```mbt check
/// test "doc: hex from digits" {
///   let h = @types.Hex::from_digits("DEAD")
///   inspect(h, content="0xdead")
/// }
/// ```
pub fn Hex::from_digits(digits : StringView) -> Hex raise CodecError {
  // the common case — an encoder's own output, or a node's answer — is already
  // in normal form, and asking that first spares it a second walk to lowercase
  let normal = if @codec.is_lower_hex_digits(digits) {
    digits
  } else {
    guard @codec.is_hex_digits(digits) else { raise InvalidHex("0x\{digits}") }
    digits.to_lower()
  }
  guard normal.length() % 2 == 0 else {
    raise InvalidLength("hex byte string must have even length: 0x\{digits}")
  }
  Hex::{ inner: "0x" + normal.to_owned() }
}

///|
/// Encode raw bytes as a `0x`-prefixed hex byte string. This is the direction
/// nothing on the wire takes — a node always answers hex — but a caller has to,
/// to hand a wallet something that was computed rather than read back: ABI
/// calldata, or a `keccak256` digest.
pub fn Hex::from_bytes(bytes : Bytes) -> Hex {
  Hex::{ inner: "0x" + @codec.digits_of_bytes(bytes) }
}

///|
/// Encode a string's UTF-8 bytes as hex — how a human-readable message is
/// handed to `personal_sign`, which takes the message as a hex byte string.
pub fn Hex::from_utf8(s : String) -> Hex {
  Hex::from_bytes(@utf8.encode(s))
}

///|
/// The canonical `0x`-prefixed lowercase string form.
pub fn Hex::to_string(self : Hex) -> String {
  self.inner
}

///|
/// The digits this value spells, without the `0x` — what a caller that works in
/// hex digits rather than in bytes wants, and what saves it from knowing how
/// long the prefix is.
pub fn Hex::digits(self : Hex) -> String {
  self.digits_view().to_owned()
}

///|
/// The two values' bytes, one after the other — a contract's creation code and
/// its constructor's arguments, above all.
///
/// Concatenation cannot fail, and this is the only way to join two `Hex` that
/// says so: taking both apart with `digits()` and putting the result back
/// through `from_digits` re-checks digits that were checked when each half was
/// built, and hands the caller an error it has no way to cause. Both rules —
/// hex digits, even length — hold of the halves, so they hold of the whole.
///
/// ```mbt check
/// test "doc: hex concat" {
///   let code = @types.Hex::from_string("0x6080")
///   inspect(code.concat(@types.Hex::from_string("0xdead")), content="0x6080dead")
/// }
/// ```
pub fn Hex::concat(self : Hex, other : Hex) -> Hex {
  Hex::{ inner: self.inner + other.digits_view().to_owned() }
}

///|
/// The digits without copying them out, for the callers inside this package
/// that only read them. The one place that knows how long the prefix is.
fn Hex::digits_view(self : Hex) -> StringView {
  self.inner[2:]
}

///|
/// The raw bytes this value spells — the reverse of `Hex::from_bytes`. Needed
/// wherever a hex byte string has to be hashed or packed alongside other
/// bytes, such as EIP-712's `encodeData`.
///
/// ```mbt check
/// test "doc: hex to bytes" {
///   let h = @types.Hex::from_string("0xdead")
///   assert_eq(h.to_bytes(), b"\xde\xad")
/// }
/// ```
pub fn Hex::to_bytes(self : Hex) -> Bytes {
  @codec.bytes_of_digits(self.digits_view())
}

///|
/// How many bytes the value holds.
pub fn Hex::byte_length(self : Hex) -> Int {
  self.digits_view().length() / 2
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
