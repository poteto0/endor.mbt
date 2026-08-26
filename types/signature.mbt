///|
/// A signature nothing signed here can carry. A recovery id of 2 or 3 says `r`
/// wrapped past the group order; `r` and `s` are a word each.
fn check_signature(
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Unit raise CodecError {
  guard y_parity == 0 || y_parity == 1 else {
    raise InvalidValue("y parity must be 0 or 1: \{y_parity}")
  }
  guard r.length() == 32 && s.length() == 32 else {
    raise InvalidValue("r and s must be 32 bytes each")
  }
}

///|
/// Append the three trailing fields a signature is, in the order every one of
/// these formats appends them. `v` is the parity bit itself, except in a legacy
/// transaction, where EIP-155 folds the chain id into it.
fn push_signature(
  fields : Array[@rlp.Item],
  v~ : UInt64,
  r~ : Bytes,
  s~ : Bytes,
) -> Unit {
  fields.push(@rlp.Item::of_uint64(v))
  fields.push(word_item(r))
  fields.push(word_item(s))
}

///|
/// A 32-byte word as the number it is: RLP writes no leading zeros, and a word
/// is trimmed here rather than routed through a `BigInt` for it.
fn word_item(word : Bytes) -> @rlp.Item {
  let mut start = 0
  while start < word.length() && word[start] == 0 {
    start += 1
  }
  Bytes(word[start:].to_owned())
}

///|
/// One half of a signature as a node spells it. `r` and `s` are quantities on
/// the wire, so a node is free to trim their leading zeros — and to leave an
/// odd number of digits behind, which is not a byte string. What they denote is
/// a word either way.
fn signature_word(j : Json, name~ : String) -> Bytes raise CodecError {
  guard j is String(s) else { raise InvalidJson("expected \{name} string") }
  // measured before the digits are walked, so an oversized value is refused
  // rather than scanned and copied first
  guard s.length() <= @codec.WORD_DIGITS + 2 else {
    raise InvalidLength("\{name} is wider than a word: \{s}")
  }
  let digits = strip_0x(s)
  @codec.word_left_pad(
    @codec.bytes_of_digits(
      if digits.length() % 2 == 0 {
        digits
      } else {
        "0" + digits
      },
    ),
  )
}

///|
/// A `yParity` field as the `Int` a signature is attached with. A value past
/// the parity bit is carried across as one that is still not a bit, rather
/// than wrapping into one: what a signature may hold is `check_signature`'s
/// to say.
fn parity_bit(v : UInt64) -> Int {
  if v <= 1 {
    v.to_int()
  } else {
    2
  }
}
