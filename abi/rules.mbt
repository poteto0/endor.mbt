///|
/// check top (256-n) bits are all zero
fn _is_valid_uint_bits_word(word : BigInt, bits : Int) -> Bool {
  if bits == 256 {
    return true
  }

  return word >> bits == 0
}

///|
/// Check top (256-n) bits are valid sign extension for intN
fn _is_valid_int_bits_word(word : BigInt, bits : Int) -> Bool {
  if bits == 256 {
    return true
  }

  let sign = (word >> (bits - 1)) & BigInt::from_int(1)
  let top = word >> bits

  if sign == 0 {
    top == 0
  } else {
    // top bits must all be 1
    let expected = (BigInt::from_int(1) << (256 - bits)) - 1
    top == expected
  }
}

///|
/// top 12 bits should be all zero
fn _is_valid_address_word(word : String) -> Bool {
  word[0:24] == "000000000000000000000000"
}

///|
/// bytesN of abi is right padded
/// size + all zero
fn _is_valid_bytes_word(word : String, size : Int) -> Bool {
  word[size * 2:] == "0".repeat(WORD_DIGITS - size * 2)
}
