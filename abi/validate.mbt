///|
/// A bit width `uintN` / `intN` can actually have.
fn _validate_bits(bits : Int, what : String) -> Int raise AbiError {
  guard bits >= 8 && bits <= 256 && bits % 8 == 0 else {
    raise InvalidAbiType(
      "\{what}\{bits}: width must be a multiple of 8 in 8..=256",
    )
  }
  bits
}

///|
/// A size `bytesN` can actually have. `bytes0` is not a type; the empty
/// dynamic `bytes` is.
fn _validate_bytes_size(n : Int) -> Int raise AbiError {
  guard n >= 1 && n <= 32 else {
    raise InvalidAbiType("bytes\{n}: size must be in 1..=32")
  }
  n
}

///|
/// A length `T[k]` can actually have.
fn _validate_array_size(k : Int) -> Int raise AbiError {
  guard k >= 0 else {
    raise InvalidAbiType("T[\{k}]: length cannot be negative")
  }
  k
}
