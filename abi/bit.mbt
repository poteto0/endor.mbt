///|
/// `2^bits` — the modulus a `uintN` lives in, and the bound its signed
/// counterpart is symmetric around.
fn _two_pow(bits : Int) -> BigInt {
  1N << bits
}

///|
/// Interprets the Most Significant Bit (MSB) as a sign bit 
/// and converts the value to a negative number if the MSB is set (Sign Extension).
/// 
/// * `val` - The raw unsigned integer value.
/// * `bits` - The bit width of the data type (e.g., 8, 16, 32).
fn _to_signed(val : BigInt, bits : Int) -> BigInt {
  if val >= _two_pow(bits - 1) {
    return val - _two_pow(bits)
  }

  val
}

///|
/// Interprets a signed value and converts it to its unsigned equivalent
/// based on the specified bit width.
/// 
/// * `val` - The raw signed integer value.
/// * `bits` - The bit width of the data type (e.g., 8, 16, 32).
fn _to_unsigned(val : BigInt, bits : Int) -> BigInt {
  if val < 0N {
    return val + _two_pow(bits)
  }

  val
}
