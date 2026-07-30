///|
/// The two digits each of the 256 byte values spells, precomputed. Every hex
/// string this package writes is a run of these, so writing a whole byte at a
/// time costs one lookup where writing digit by digit costs a branch and a
/// buffer append per nibble.
let byte_digits : FixedArray[String] = FixedArray::makei(256, n => {
  n.to_byte().to_hex()
})

///|
/// The value of one hex digit. Total on purpose: every character reached here
/// came from a validated `@types.Hex` or from an encoder that only writes
/// digits, so a non-hex character cannot occur, and raising for it would put an
/// impossible error case in every caller's signature.
pub fn nibble(c : Char) -> Int {
  nibble_of_code(c.to_int())
}

///|
/// `nibble`, over a UTF-16 code unit rather than a `Char` — what reading a hex
/// string by index gives, and what `bytes_of_digits` walks. Every hex digit is
/// ASCII, so the two agree wherever the input really is one.
fn nibble_of_code(u : Int) -> Int {
  match u {
    0x30..=0x39 => u - 0x30 // '0'..='9'
    0x61..=0x66 => u - 0x61 + 10 // 'a'..='f'
    0x41..=0x46 => u - 0x41 + 10 // 'A'..='F'
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
    buf.write_string(byte_digits[b.to_int()])
  }
  buf.to_string()
}

///|
/// The bytes an even-length run of hex digits spells. Total for the same reason
/// `nibble` is: a trailing half byte is dropped rather than raising, because
/// every caller either holds a validated `@types.Hex` or slices whole words out
/// of one.
///
/// Takes a view so a caller that holds the digits inside a longer string — a
/// `@types.Hex` holds them after its `0x` — can hand over the part it means
/// without copying it out first.
pub fn bytes_of_digits(digits : StringView) -> Bytes {
  Bytes::makei(digits.length() / 2, i => {
    let high = nibble_of_code(digits.unsafe_get(i * 2).to_int())
    let low = nibble_of_code(digits.unsafe_get(i * 2 + 1).to_int())
    ((high << 4) | low).to_byte()
  })
}

///|
/// Whether every character of `s` is a hex digit. The alphabet half of the
/// wire's spelling rule, asked on its own by a caller that already holds the
/// digits rather than a `0x`-prefixed string.
pub fn is_hex_digits(s : StringView) -> Bool {
  scan_digits(s, lower_only=false)
}

///|
/// Whether `s` is hex digits already in their normal form — no uppercase, so
/// nothing has to be lowercased. Everything this package writes is, so a caller
/// that would otherwise validate and then lowercase can ask both questions in
/// the one pass this answers in.
pub fn is_lower_hex_digits(s : StringView) -> Bool {
  scan_digits(s, lower_only=true)
}

///|
/// The pass both predicates above are: one walk over the code units, since a
/// hex digit is ASCII and decoding each into a `Char` costs more than the test.
fn scan_digits(s : StringView, lower_only~ : Bool) -> Bool {
  for i in 0..<s.length() {
    let u = s.unsafe_get(i).to_int()
    let ok = (u >= 0x30 && u <= 0x39) || // '0'..='9'
      (u >= 0x61 && u <= 0x66) || // 'a'..='f'
      (!lower_only && u >= 0x41 && u <= 0x46) // 'A'..='F'
    guard ok else { return false }
  }
  true
}

///|
/// The digits of a `0x`-prefixed hex value, or `None` when the string is not
/// one: the prefix and the alphabet are the wire's spelling rules, so every
/// layer that parses hex — `@types.Hex` and `Address`, a quantity, an EIP-712
/// document's wide integers — asks the same question here and raises whichever
/// error is its own.
pub fn hex_body(s : String) -> String? {
  guard s.has_prefix("0x") else { return None }
  let body = s[2:]
  guard is_hex_digits(body) else { return None }
  Some(body.to_owned())
}
