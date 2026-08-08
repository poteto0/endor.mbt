///|
/// The halves as one string, so a `None` and a split are one comparison.
fn parts(s : String) -> String {
  match @codec.decimal_parts(s[:]) {
    Some((int_digits, frac_digits)) =>
      "\{int_digits.to_owned()}|\{frac_digits.to_owned()}"
    None => "not a number"
  }
}

///|
/// The grammar, which is narrower than "anything a human might type": the layer
/// above turns a `None` into whichever error names the value.
test "decimal_parts splits only a plain decimal number" {
  inspect(parts("1.5"), content="1|5")
  inspect(parts("12"), content="12|")
  // a point on either end is still a number, with one empty half
  inspect(parts("12."), content="12|")
  inspect(parts(".5"), content="|5")
  // and what is not one
  inspect(parts(""), content="not a number")
  inspect(parts("."), content="not a number")
  inspect(parts("1.2.3"), content="not a number")
  inspect(parts("-1"), content="not a number")
  inspect(parts("1e18"), content="not a number")
  inspect(parts("1_000"), content="not a number")
  inspect(parts(" 1"), content="not a number")
}

///|
/// Moving the point right: what the digits become, before anybody reads them as
/// a number.
test "decimal_scale pads out to the full width" {
  assert_eq(
    @codec.decimal_scale("1", "5", decimals=18),
    Some("1500000000000000000"),
  )
  assert_eq(@codec.decimal_scale("1", "", decimals=6), Some("1000000"))
  assert_eq(@codec.decimal_scale("", "5", decimals=6), Some("500000"))
  // no scale at all leaves the digits alone
  assert_eq(@codec.decimal_scale("12", "", decimals=0), Some("12"))
  // exactly as fine as the scale allows: nothing left to pad
  assert_eq(@codec.decimal_scale("0", "000001", decimals=6), Some("0000001"))
  // one digit finer is not a number this scale can carry
  assert_eq(@codec.decimal_scale("0", "0000001", decimals=6), None)
  assert_eq(@codec.decimal_scale("1", "5", decimals=0), None)
}

///|
/// And back, with the convention this package fixes: trailing zeros fold, and a
/// fraction that is all of them takes the point with it.
test "decimal_unscale folds trailing zeros" {
  inspect(
    @codec.decimal_unscale("1500000000000000000", decimals=18),
    content="1.5",
  )
  inspect(
    @codec.decimal_unscale("1000000000000000000", decimals=18),
    content="1",
  )
  inspect(@codec.decimal_unscale("1500000", decimals=6), content="1.5")
  inspect(@codec.decimal_unscale("1234560", decimals=6), content="1.23456")
  // narrower than the scale: the zeros in front of the point are written out
  inspect(
    @codec.decimal_unscale("1", decimals=18),
    content="0.000000000000000001",
  )
  inspect(@codec.decimal_unscale("0", decimals=18), content="0")
  // no scale: the digits are the number
  inspect(@codec.decimal_unscale("1234", decimals=0), content="1234")
}

///|
/// The round trip, which is the property both functions exist for.
test "a decimal survives being scaled and unscaled" {
  for written in ["0", "1", "1.5", "0.000000000000000001", "123456.789"] {
    guard @codec.decimal_parts(written[:]) is Some((int_digits, frac_digits)) else {
      fail("\{written} should be a decimal number")
    }
    guard @codec.decimal_scale(int_digits, frac_digits, decimals=18)
      is Some(scaled) else {
      fail("18 decimals should carry \{written}")
    }
    assert_eq(@codec.decimal_unscale(scaled[:], decimals=18), written)
  }
}
