///|
/// `n` zero digits, the padding every word is built from.
fn _zeros(n : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<n {
    out.write_char('0')
  }
  out.to_string()
}

///|
/// Right-align digits in one 32-byte word — where a number or an address goes.
fn _left_pad(digits : String) -> String {
  _zeros(WORD_DIGITS - digits.length()) + digits
}

///|
/// Left-align digits and pad out to whole words — where raw bytes go, both the
/// `bytesN` that fit one word and the `bytes` that follow a length.
fn _right_pad(digits : String) -> String {
  let remainder = digits.length() % WORD_DIGITS
  if remainder == 0 {
    digits
  } else {
    digits + _zeros(WORD_DIGITS - remainder)
  }
}
