///|
/// A 256-bit unsigned quantity of wei (smallest ETH unit), backed by `BigInt`.
/// Carried on the wire as a minimal `0x`-prefixed hex quantity.
pub struct Wei {
  priv value : BigInt
} derive(Eq, Debug)

///|
/// Build a wei amount from a small non-negative integer.
pub fn Wei::from_int(n : Int) -> Wei {
  Wei::{ value: BigInt::from_int(n) }
}

///|
/// Build a wei amount from a `BigInt`.
pub fn Wei::from_bigint(n : BigInt) -> Wei {
  Wei::{ value: n }
}

///|
/// The underlying `BigInt` value.
pub fn Wei::to_bigint(self : Wei) -> BigInt {
  self.value
}

///|
/// Zero wei.
pub fn Wei::zero() -> Wei {
  Wei::{ value: BigInt::from_int(0) }
}

///|
/// Parse a `0x`-prefixed hex quantity into a wei amount.
pub fn Wei::from_hex(s : String) -> Wei raise CodecError {
  let body = strip_0x(s)
  guard body.length() > 0 else { raise InvalidHex("empty wei quantity: \{s}") }
  Wei::{ value: BigInt::from_string(body, radix=16) }
}

///|
/// Encode as a minimal `0x`-prefixed hex quantity.
pub fn Wei::to_hex(self : Wei) -> String {
  "0x" + self.value.to_string(radix=16)
}

///|
/// Read a decimal amount written the way a human writes one — `"1.5"`, `"0.05"`
/// — as the integer of `10^-decimals` units it stands for.
///
/// The amount is a `String` and not a `Double` on purpose: `0.1` is not
/// representable in binary, so a `Double` has already lost the value before
/// this could see it, and the digit that goes missing in a token amount is a
/// digit of somebody's money.
///
/// An amount finer than `decimals` **raises** rather than being truncated:
/// dropping digits the caller wrote is the one failure that would be silent.
///
/// ```
/// let amount = @types.Wei::from_units("1.5", decimals=18)
/// inspect(amount.to_bigint(), content="1500000000000000000")
/// // six decimals is USDC and every stablecoin like it
/// inspect(@types.Wei::from_units("1.5", decimals=6).to_bigint(), content="1500000")
/// ```
pub fn Wei::from_units(value : String, decimals~ : Int) -> Wei raise CodecError {
  guard decimals >= 0 else {
    raise InvalidDecimal("decimals cannot be negative: \{decimals}")
  }
  guard @codec.decimal_parts(value) is Some((int_digits, frac_digits)) else {
    raise InvalidDecimal("not a decimal amount: \{value}")
  }
  guard frac_digits.length() <= decimals else {
    raise InvalidDecimal(
      "\{value} is finer than \{decimals} decimals: it names \{frac_digits.length()}",
    )
  }
  Wei::{
    value: BigInt::from_string(
      @codec.decimal_scale(int_digits, frac_digits, decimals~),
    ),
  }
}

///|
/// Write the amount back as a decimal string, `decimals` places from the right.
///
/// Trailing zeros are folded: at 18 decimals `1500000000000000000` is `"1.5"`
/// and `1000000000000000000` is `"1"`. What comes back is the number and
/// nothing else — no thousands separators, no symbol, no padding to a fixed
/// width. Those are the application's, and an SDK that formatted them would be
/// wrong in some locale.
///
/// ```
/// let balance = @types.Wei::from_int(1500000)
/// inspect(balance.to_units(decimals=6), content="1.5")
/// ```
pub fn Wei::to_units(self : Wei, decimals~ : Int) -> String {
  let digits = self.value.to_string()
  if decimals <= 0 {
    digits
  } else {
    @codec.decimal_unscale(digits[:], decimals~)
  }
}

///|
/// `from_units` at 18 decimals — ether, the unit a chain's own balances and
/// values are quoted in.
///
/// ```
/// inspect(@types.Wei::from_ether("0.05").to_bigint(), content="50000000000000000")
/// ```
pub fn Wei::from_ether(value : String) -> Wei raise CodecError {
  Wei::from_units(value, decimals=ETHER_DECIMALS)
}

///|
/// `to_units` at 18 decimals.
///
/// ```
/// inspect(@types.Wei::from_ether("0.05").to_ether(), content="0.05")
/// ```
pub fn Wei::to_ether(self : Wei) -> String {
  self.to_units(decimals=ETHER_DECIMALS)
}

///|
/// `from_units` at 9 decimals — gwei, which is how a gas price is quoted
/// everywhere a human reads one.
///
/// ```
/// inspect(@types.Wei::from_gwei("21.5").to_bigint(), content="21500000000")
/// ```
pub fn Wei::from_gwei(value : String) -> Wei raise CodecError {
  Wei::from_units(value, decimals=GWEI_DECIMALS)
}

///|
/// `to_units` at 9 decimals.
///
/// ```
/// inspect(@types.Wei::from_gwei("21.5").to_gwei(), content="21.5")
/// ```
pub fn Wei::to_gwei(self : Wei) -> String {
  self.to_units(decimals=GWEI_DECIMALS)
}

///|
/// The two scales the chain itself fixes. A token's own `decimals` is whatever
/// the token says — `Erc20::decimals` reads it — and is passed to `from_units`
/// rather than named here.
const ETHER_DECIMALS : Int = 18

///|
const GWEI_DECIMALS : Int = 9

///|
/// Encode as a JSON hex-quantity string.
pub fn Wei::to_json(self : Wei) -> Json {
  Json::string(self.to_hex())
}

///|
/// Decode from a JSON hex-quantity string.
pub fn Wei::from_json(j : Json) -> Wei raise CodecError {
  match j {
    String(s) => Wei::from_hex(s)
    _ => raise InvalidJson("expected wei string")
  }
}

///|
pub impl Show for Wei with fn output(self, logger) {
  logger.write_string("Wei(\{self.value})")
}
