///|
/// The two halves of a plain decimal number — the digits before the point and
/// the digits after it — or `None` when `s` is not one.
///
/// The grammar is narrow: decimal digits, at most one `.`, at least one digit,
/// nothing else. No sign, no exponent, no separators. Either half may be empty
/// (`"1."`, `".5"`).
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
  let halves = if point < 0 { (s, s[0:0]) } else { (s[0:point], s[point + 1:]) }
  // one digit at least: neither `""` nor `"."` is a number
  guard halves.0.length() + halves.1.length() > 0 else { return None }
  Some(halves)
}

///|
/// The integer `int_digits.frac_digits` becomes when the point moves `decimals`
/// places to the right: the two runs of digits, concatenated, padded on the
/// right with however many zeros are left over.
///
/// `None` when `frac_digits` is longer than `decimals`. What to say about that
/// is the caller's; the rule itself is stated here.
pub fn decimal_scale(
  int_digits : StringView,
  frac_digits : StringView,
  decimals~ : Int,
) -> String? {
  guard frac_digits.length() <= decimals else { return None }
  Some(
    int_digits.to_owned() +
    frac_digits.to_owned() +
    zeros_on_positive(decimals - frac_digits.length()),
  )
}

///|
/// The inverse: `digits` read as a value scaled by `10^decimals`, written back
/// with the point where it belongs. A `decimals` of zero or less is no scale at
/// all, and the digits are the number.
///
/// Trailing zeros in the fraction are folded, and an all-zero fraction takes the
/// point with it: at 18 decimals `1500000000000000000` is `"1.5"`.
pub fn decimal_unscale(digits : StringView, decimals~ : Int) -> String {
  guard decimals > 0 else { return digits.to_owned() }
  // where the point falls, plus the zeros in front of a fraction narrower than
  // the scale: 1 unit of a 6-decimal token is "0.000001"
  let point = if digits.length() > decimals {
    digits.length() - decimals
  } else {
    0
  }
  let leading = zeros_on_positive(decimals - digits.length())
  // `leading` is zeros throughout, so a `tail` that folds away takes it along
  let tail = digits[point:].trim_end(chars="0")
  let buf = StringBuilder::new()
  if point == 0 {
    buf.write_char('0')
  } else {
    buf.write_view(digits[0:point])
  }
  if !tail.is_empty() {
    buf.write_char('.')
    buf.write_string(leading)
    buf.write_view(tail)
  }
  buf.to_string()
}
