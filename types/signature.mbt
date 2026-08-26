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
