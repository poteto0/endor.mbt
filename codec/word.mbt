///|
/// How wide one ABI word is. Everything the ABI encodes — and everything
/// EIP-712 hashes — is laid out in words this size, so both the byte-level
/// padding below and the digit count beside it start here.
pub const WORD_BYTES = 32

///|
/// How many hex digits one word takes. `abi` works in hex digits throughout —
/// `Hex` is a hex string, so staying in that alphabet keeps encoding and
/// decoding to slicing rather than byte arithmetic.
pub const WORD_DIGITS : Int = WORD_BYTES * 2

///|
/// How many bits one word holds — the width every value on the wire ends up at.
pub const WORD_BITS : Int = WORD_BYTES * 8

///|
/// `2^bits`, the modulus a `uintN` lives in — and, one bit down, the bound its
/// signed counterpart is symmetric around.
fn two_pow(bits : Int) -> BigInt {
  1N << bits
}

///|
/// One word's bits read as a signed value: the top bit is the sign, so anything
/// at or above `2^255` is that much below zero (two's complement).
///
/// A narrower `intN` is sign-extended to the whole word on the wire, so the
/// width never enters here — which is why `abi`'s `int8` and EIP-712's `int256`
/// can share one function.
pub fn word_to_signed(val : BigInt) -> BigInt {
  if val >= two_pow(WORD_BITS - 1) {
    val - two_pow(WORD_BITS)
  } else {
    val
  }
}

///|
/// A signed value as the word that spells it: unchanged if it is already
/// non-negative, `val + 2^256` otherwise.
pub fn word_to_unsigned(val : BigInt) -> BigInt {
  if val < 0N {
    val + two_pow(WORD_BITS)
  } else {
    val
  }
}

///|
/// `n` as a big-endian word. `n` must already be non-negative and below
/// `2^256`, which `word_to_unsigned` is how a caller arranges.
pub fn word_of_unsigned(n : BigInt) -> Bytes {
  n.to_octets(length=WORD_BYTES)
}

///|
/// Right-align `bytes` within one word — where a number or an address goes,
/// for the caller that works in bytes (EIP-712 hashes them; it does not slice
/// them).
pub fn word_left_pad(bytes : Bytes) -> Bytes {
  let pad = WORD_BYTES - bytes.length()
  Bytes::makei(WORD_BYTES, i => if i < pad { b'\x00' } else { bytes[i - pad] })
}

///|
/// Left-align `bytes` within one word and zero-fill the rest — where
/// `bytes1`..`bytes32` go.
pub fn word_right_pad(bytes : Bytes) -> Bytes {
  Bytes::makei(WORD_BYTES, i => {
    if i < bytes.length() {
      bytes[i]
    } else {
      b'\x00'
    }
  })
}

///|
/// Concatenate a run of words. Every element EIP-712's `encodeData` and
/// `encodeValue` produce is exactly one word, which is what lets concatenation
/// be this simple.
pub fn concat_words(words : Array[Bytes]) -> Bytes {
  Bytes::makei(words.length() * WORD_BYTES, i => {
    words[i / WORD_BYTES][i % WORD_BYTES]
  })
}

///|
/// Right-align digits within one word — the same rule as `word_left_pad`, for
/// the caller that works in hex digits.
pub fn digits_left_pad(digits : String) -> String {
  zeros(WORD_DIGITS - digits.length()) + digits
}

///|
/// Left-align digits and pad out to whole words — where raw bytes go, both the
/// `bytesN` that fit one word and the `bytes` that follow a length. Unlike
/// `word_right_pad` this spans as many words as the content needs, because the
/// ABI writes dynamic content inline where EIP-712 hashes it down to one word.
pub fn digits_right_pad(digits : String) -> String {
  let remainder = digits.length() % WORD_DIGITS
  if remainder == 0 {
    digits
  } else {
    digits + zeros(WORD_DIGITS - remainder)
  }
}

///|
/// One word's worth of zero digits. Padding is most of what an encoded word is,
/// and both functions above ask for at most a word of it, so the run is written
/// once here and sliced. Core's `pad_start` would read better, but it fills a
/// character at a time and the `js` backend turns that into one string concat
/// per digit — around 20× the cost, on the hottest loop the encoder has.
let word_zeros : String = "0".repeat(WORD_DIGITS)

///|
/// `n` zero digits, for `n` in `0..=WORD_DIGITS`. Negative asks for none: a
/// value that already fills its word needs no padding.
fn zeros(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    word_zeros[:n].to_owned()
  }
}
