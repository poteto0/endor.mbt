///|
/// Read ABI-encoded data back as the types it was declared to hold — a
/// contract's return data, or the non-indexed part of an event's payload.
///
/// Nothing in the data says what it is, so the types are what makes it
/// readable. Data that does not fit them raises `InvalidData` rather than
/// answering with a truncated or invented value: a contract whose ABI says one
/// thing and whose answer says another is a mismatch worth hearing about.
///
/// ```
/// let values = @abi.decode(
///   [Uint(256)],
///   @types.Hex::from_string(
///     "0x000000000000000000000000000000000000000000000000000000000000002a",
///   ),
/// )
/// inspect(values, content="[Uint(42)]")
/// ```
pub fn decode(
  types : Array[AbiType],
  data : @types.Hex,
) -> Array[AbiValue] raise AbiError {
  _decode_block(types, data.digits(), 0)
}

///|
/// Read a run of values from the block starting at `base`: each head is either
/// the value itself or the offset — counted from `base` — of its tail.
fn _decode_block(
  types : Array[AbiType],
  data : String,
  base : Int,
) -> Array[AbiValue] raise AbiError {
  let out = []
  let mut at = base
  for t in types {
    let where_ = if t.is_dynamic() {
      base + _read_index(data, at, what="offset") * 2
    } else {
      at
    }
    out.push(_decode_value(t, data, where_))
    at += t.head_digits()
  }
  out
}

///|
/// Read one value of type `t` from the digits at `at`.
fn _decode_value(
  t : AbiType,
  data : String,
  at : Int,
) -> AbiValue raise AbiError {
  match t {
    Uint(bits) => {
      ignore(AbiType::checked_bits(bits, what="uint"))
      Uint(_read_word_as_uint(data, at))
    }
    Int(bits) => {
      ignore(AbiType::checked_bits(bits, what="int"))
      let raw = _read_word_as_uint(data, at)
      // two's complement over the whole word: the top bit is the sign
      Int(@codec.word_to_signed(raw))
    }
    AbiType::Address => {
      let word = _read_word(data, at)
      Address(
        @types.Address::from_string("0x" + word[WORD_DIGITS - 40:].to_owned()) catch {
          e => raise InvalidData("address: \{e}")
        },
      )
    }
    AbiType::Bool =>
      match _read_word_as_uint(data, at).to_string() {
        "0" => Bool(false)
        "1" => Bool(true)
        other => raise InvalidData("bool must be 0 or 1, got \{other}")
      }
    FixedBytes(size) => {
      let word = _read_word(data, at)
      Bytes(
        @codec.bytes_of_digits(word[:AbiType::checked_bytes_size(size) * 2]),
      )
    }
    AbiType::Bytes => Bytes(_read_byte_string(data, at))
    AbiType::String =>
      String(
        @utf8.decode(_read_byte_string(data, at)) catch {
          _ => raise InvalidData("string is not valid UTF-8")
        },
      )
    Array(elem) => {
      let length = _read_index(data, at, what="array length")
      Array(_decode_block(Array::make(length, elem), data, at + WORD_DIGITS))
    }
    FixedArray(elem, size) =>
      Array(
        _decode_block(
          Array::make(AbiType::checked_array_size(size), elem),
          data,
          at,
        ),
      )
    Tuple(elems) => Tuple(_decode_block(elems, data, at))
  }
}

///|
/// The 32-byte word at `at`, or `InvalidData` when the data stops short of it.
fn _read_word(data : String, at : Int) -> String raise AbiError {
  guard at >= 0 && at + WORD_DIGITS <= data.length() else {
    raise InvalidData(
      "expected a word at byte \{at / 2}, but the data is \{data.length() / 2} bytes",
    )
  }
  data[at:at + WORD_DIGITS].to_owned()
}

///|
/// The word at `at` read as an unsigned 256-bit number.
fn _read_word_as_uint(data : String, at : Int) -> BigInt raise AbiError {
  BigInt::from_string(_read_word(data, at), radix=16)
}

///|
/// A word read as a position or a count, in bytes.
///
/// Both are `uint256` on the wire and both have to become an `Int` to index
/// with, so anything that could not possibly address this data is rejected here
/// rather than truncated into a plausible-looking small number.
fn _read_index(data : String, at : Int, what~ : String) -> Int raise AbiError {
  let word = _read_word(data, at)
  let mut value = 0
  for i, c in word.iter2() {
    let digit = @codec.nibble(c)
    // only the last 6 digits can address data this side of 16 MB, so anything
    // above them is out of range by construction — and keeps `value` in `Int`
    // top top 58 bits must be all 0
    if i < WORD_DIGITS - 6 {
      guard digit == 0 else {
        raise InvalidData("\{what} is far larger than the data")
      }
    } else {
      value = value * 16 + digit
    }
  }
  guard value <= data.length() / 2 else {
    raise InvalidData(
      "\{what} \{value} is past the end of \{data.length() / 2} bytes",
    )
  }
  value
}

///|
/// A dynamic byte string: a length word, then that many bytes.
fn _read_byte_string(data : String, at : Int) -> Bytes raise AbiError {
  let length = _read_index(data, at, what="byte length")
  let from = at + WORD_DIGITS
  guard from + length * 2 <= data.length() else {
    raise InvalidData(
      "\{length} bytes claimed at byte \{from / 2}, past the end of \{data.length() / 2} bytes",
    )
  }
  @codec.bytes_of_digits(data[from:from + length * 2])
}
