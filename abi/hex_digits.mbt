///|
/// The value of one hex digit. Total on purpose: every string this package
/// slices came from a validated `Hex` or from its own encoder, so a
/// non-hex character cannot reach here, and raising for it would put an
/// impossible error case in every caller's signature.
fn nibble(c : Char) -> Int {
  match c {
    '0'..='9' => c.to_int() - '0'.to_int()
    'a'..='f' => c.to_int() - 'a'.to_int() + 10
    'A'..='F' => c.to_int() - 'A'.to_int() + 10
    _ => 0
  }
}

///|
/// The digits of a `0x`-prefixed value — the one place this package knows what
/// that prefix is, so `Hex` and `Address` are sliced the same way everywhere.
fn digits_of(prefixed : String) -> String {
  prefixed[2:].to_owned()
}

///|
/// Bytes as the hex digits that spell them — the same encoding `Hex` itself is,
/// with the prefix taken back off.
fn digits_of_bytes(bytes : Bytes) -> String {
  digits_of(@types.Hex::from_bytes(bytes).to_string())
}

///|
/// The bytes an even-length run of hex digits spells.
fn bytes_of_digits(digits : String) -> Bytes {
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
/// `n` zero digits, the padding every word is built from.
fn zeros(n : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<n {
    out.write_char('0')
  }
  out.to_string()
}

///|
/// Right-align digits in one 32-byte word — where a number or an address goes.
fn left_pad(digits : String) -> String {
  zeros(WORD_DIGITS - digits.length()) + digits
}

///|
/// Left-align digits and pad out to whole words — where raw bytes go, both the
/// `bytesN` that fit one word and the `bytes` that follow a length.
fn right_pad(digits : String) -> String {
  let remainder = digits.length() % WORD_DIGITS
  if remainder == 0 {
    digits
  } else {
    digits + zeros(WORD_DIGITS - remainder)
  }
}
