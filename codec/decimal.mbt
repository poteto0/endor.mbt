///|
/// The two halves of a plain decimal number — the digits before the point and
/// the digits after it — or `None` when `s` is not one.
///
/// The grammar is deliberately narrow: decimal digits, at most one `.`, at
/// least one digit somewhere, and nothing else. No sign (the quantities this
/// serves are unsigned), no exponent, no separators — a caller writing `1e18`
/// or `1_000` means something the wire has no notion of, and reading it as `1`
/// would be worse than refusing it.
///
/// Either half may be empty (`"1."`, `".5"`), so a caller that wants to reject
/// those still can, and the two below do not have to care.
pub fn decimal_parts(s : StringView) -> (StringView, StringView)? {
  let mut point = -1
  for i in 0..<s.length() {
    let u = s.unsafe_get(i).to_int()
    if u == 0x2e { // '.'
      guard point < 0 else { return None }
      point = i
    } else {
      guard u >= 0x30 && u <= 0x39 else { return None } // '0'..='9'
    }
  }
  // one digit at least: neither `""` nor `"."` is a number
  guard s.length() > (if point < 0 { 0 } else { 1 }) else { return None }
  if point < 0 {
    Some((s, s[0:0]))
  } else {
    Some((s[0:point], s[point + 1:]))
  }
}

///|
/// The integer `int_digits.frac_digits` becomes when the point moves `decimals`
/// places to the right: the two runs of digits, concatenated, padded on the
/// right with however many zeros are left over.
///
/// A `frac_digits` longer than `decimals` is digits the target cannot hold, and
/// this does not decide what to do about that — the rule belongs to the caller,
/// and `@types.Wei::from_units` raises rather than dropping them silently.
/// Handed a longer one anyway, it keeps the extra digits, which is the wrong
/// scale: ask `frac_digits.length() <= decimals` first.
pub fn decimal_scale(
  int_digits : StringView,
  frac_digits : StringView,
  decimals~ : Int,
) -> String {
  let buf = StringBuilder::new()
  buf.write_view(int_digits)
  buf.write_view(frac_digits)
  write_zeros(buf, decimals - frac_digits.length())
  buf.to_string()
}

///|
/// The inverse: `digits` read as a value scaled by `10^decimals`, written back
/// with the point where it belongs.
///
/// Trailing zeros in the fraction are folded, and a fraction that is all zeros
/// takes the point with it — at 18 decimals `1500000000000000000` is `"1.5"`
/// and `1000000000000000000` is `"1"`, not `"1.500000000000000000"`. That is
/// the one convention here: a caller wanting a fixed number of places is
/// formatting for a human to read, which is its business and not this
/// package's.
pub fn decimal_unscale(digits : StringView, decimals~ : Int) -> String {
  guard decimals > 0 else { return digits.to_owned() }
  // the point needs a digit on each side of it, whatever the value's own width
  let buf = StringBuilder::new()
  write_zeros(buf, decimals + 1 - digits.length())
  buf.write_view(digits)
  let padded = buf.to_string()
  let point = padded.length() - decimals
  let mut end = padded.length()
  while end > point && padded.unsafe_get(end - 1).to_int() == 0x30 {
    end = end - 1
  }
  if end == point {
    padded[0:point].to_owned()
  } else {
    padded[0:point].to_owned() + "." + padded[point:end].to_owned()
  }
}

///|
fn write_zeros(buf : StringBuilder, n : Int) -> Unit {
  for _ in 0..<n {
    buf.write_char('0')
  }
}
