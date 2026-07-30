///|
/// The hex alphabet, as a `FixedArray` so a nibble can index it.
let hex_digit : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
/// The value of one hex digit. Total on purpose: every character reached here
/// came from a validated `@types.Hex` or from an encoder that only writes
/// digits, so a non-hex character cannot occur, and raising for it would put an
/// impossible error case in every caller's signature.
pub fn nibble(c : Char) -> Int {
  match c {
    '0'..='9' => c.to_int() - '0'.to_int()
    'a'..='f' => c.to_int() - 'a'.to_int() + 10
    'A'..='F' => c.to_int() - 'A'.to_int() + 10
    _ => 0
  }
}

///|
/// Bytes as the hex digits that spell them, with no `0x` — the primitive
/// `@types.Hex::from_bytes` puts the prefix on, and what `abi` packs into a
/// word.
pub fn digits_of_bytes(bytes : Bytes) -> String {
  let buf = StringBuilder::new()
  for b in bytes {
    let n = b.to_int()
    buf.write_char(hex_digit[n >> 4])
    buf.write_char(hex_digit[n & 0x0f])
  }
  buf.to_string()
}

///|
/// The bytes an even-length run of hex digits spells. Total for the same reason
/// `nibble` is: a trailing half byte is dropped rather than raising, because
/// every caller either holds a validated `@types.Hex` or slices whole words out
/// of one.
pub fn bytes_of_digits(digits : String) -> Bytes {
  let out = Array::new(capacity=digits.length() / 2)
  let mut high = 0
  for i, c in digits.iter2() {
    if i % 2 == 0 {
      high = nibble(c)
    } else {
      out.push(((high << 4) | nibble(c)).to_byte())
    }
  }
  Bytes::makei(out.length(), i => out[i])
}

///|
/// The digits of a `0x`-prefixed hex value, or `None` when the string is not
/// one: the prefix and the alphabet are the wire's spelling rules, so every
/// layer that parses hex — `@types.Hex` and `Address`, a quantity, an EIP-712
/// document's wide integers — asks the same question here and raises whichever
/// error is its own.
pub fn hex_body(s : String) -> String? {
  guard s.has_prefix("0x") else { return None }
  let body = s[2:].to_owned()
  for c in body {
    guard c.is_ascii_hexdigit() else { return None }
  }
  Some(body)
}
