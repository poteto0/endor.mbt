///|
/// Whether `bits` is a width `uintN` / `intN` can actually have.
///
/// This and the four below are the ABI's rules as plain predicates, with no
/// error type of their own: the layer that holds `AbiType` turns them into an
/// `AbiError`, `@eip712` into a `CodecError`. One answer per rule.
pub fn is_valid_bits(bits : Int) -> Bool {
  bits >= 8 && bits <= 256 && bits % 8 == 0
}

///|
/// Whether `n` is a size `bytesN` can actually have. `bytes0` is not a type;
/// the empty dynamic `bytes` is.
pub fn is_valid_bytes_size(n : Int) -> Bool {
  n >= 1 && n <= WORD_BYTES
}

///|
/// Whether `k` is a length `T[k]` can actually have.
pub fn is_valid_array_size(k : Int) -> Bool {
  k >= 0
}

///|
/// Whether a `uintN` of this width holds `n`.
pub fn fits_uint(n : BigInt, bits~ : Int) -> Bool {
  n >= 0N && n < two_pow(bits)
}

///|
/// Whether an `intN` of this width holds `n` — two's complement, so the range
/// is one wider below zero than above.
pub fn fits_int(n : BigInt, bits~ : Int) -> Bool {
  let half = two_pow(bits - 1)
  n >= -half && n < half
}
