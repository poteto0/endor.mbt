///|
/// Zero, to compare a `BigInt` against without building one each time.
let zero : BigInt = 0N

///|
/// `2^bits` — the modulus a `uintN` lives in, and the bound its signed
/// counterpart is symmetric around.
fn two_pow(bits : Int) -> BigInt {
  1N << bits
}

///|
/// ABI-encode a list of values against the types they are declared as — the
/// argument list of a call, or the return list of one.
///
/// The types come alongside the values because the encoding depends on them:
/// only the type says whether a `uint` is 8 or 256 bits wide (and therefore
/// whether the value fits), and only the type tells a fixed-length array from a
/// dynamic one, which decides whether the value is written inline or as an
/// offset into the tail.
///
/// ```
/// let data = @abi.encode(
///   [Address, Uint(256)],
///   [
///     Address(@types.Address::from_string("0x000000000000000000000000000000000000dead")),
///     Uint(1N),
///   ],
/// )
/// inspect(
///   data,
///   content=(
///     "0x000000000000000000000000000000000000000000000000000000000000dead" +
///     "0000000000000000000000000000000000000000000000000000000000000001"
///   ),
/// )
/// ```
pub fn encode(
  types : Array[AbiType],
  values : Array[AbiValue],
) -> @types.Hex raise AbiError {
  @types.Hex::from_bytes(bytes_of_digits(encode_block(types, values)))
}

///|
/// Encode a run of values as one block: every head first — inline for a static
/// type, the offset of its tail for a dynamic one — then every tail.
///
/// Offsets are counted from the start of this block, not of the whole message,
/// which is what lets the same function encode a top-level argument list, a
/// tuple and an array's elements.
fn encode_block(
  types : Array[AbiType],
  values : Array[AbiValue],
) -> String raise AbiError {
  guard types.length() == values.length() else {
    raise InvalidValue(
      "expected \{types.length()} values, got \{values.length()}",
    )
  }
  let head_digits = types.iter().fold(init=0, (sum, t) => sum + t.head_digits())
  let heads = []
  let tails = []
  let mut tail_digits = 0
  for i, t in types {
    if t.is_dynamic() {
      let offset = (head_digits + tail_digits) / 2
      heads.push(left_pad(offset.to_string(radix=16)))
      let tail = encode_value(t, values[i])
      tail_digits += tail.length()
      tails.push(tail)
    } else {
      heads.push(encode_value(t, values[i]))
    }
  }
  let out = StringBuilder::new()
  for part in heads {
    out.write_string(part)
  }
  for part in tails {
    out.write_string(part)
  }
  out.to_string()
}

///|
/// Encode one value, in the layout its own type calls for: a single word for a
/// scalar, a length word plus padded content for a byte string, and a nested
/// block for anything compound.
fn encode_value(t : AbiType, v : AbiValue) -> String raise AbiError {
  match (t, v) {
    (Uint(bits), Uint(n)) => {
      guard n >= zero && n < two_pow(check_bits(bits, "uint")) else {
        raise InvalidValue("uint\{bits} cannot hold \{n}")
      }
      left_pad(n.to_string(radix=16))
    }
    (Int(bits), Int(n)) => {
      let half = two_pow(check_bits(bits, "int") - 1)
      guard n >= zero - half && n < half else {
        raise InvalidValue("int\{bits} cannot hold \{n}")
      }
      // two's complement: a negative value is the word that many below 2^256
      left_pad(
        (if n < zero { n + two_pow(256) } else { n }).to_string(radix=16),
      )
    }
    (AbiType::Address, AbiValue::Address(a)) =>
      left_pad(digits_of(a.to_string()))
    (AbiType::Bool, AbiValue::Bool(b)) => left_pad(if b { "1" } else { "0" })
    (FixedBytes(size), Bytes(b)) => {
      guard b.length() == check_bytes_size(size) else {
        raise InvalidValue(
          "bytes\{size} needs \{size} bytes, got \{b.length()}",
        )
      }
      right_pad(digits_of_bytes(b))
    }
    (AbiType::Bytes, AbiValue::Bytes(b)) =>
      left_pad(b.length().to_string(radix=16)) + right_pad(digits_of_bytes(b))
    (AbiType::String, AbiValue::String(s)) =>
      encode_value(AbiType::Bytes, AbiValue::Bytes(@utf8.encode(s)))
    (Array(elem), Array(xs)) =>
      left_pad(xs.length().to_string(radix=16)) +
      encode_block(Array::make(xs.length(), elem), xs)
    (FixedArray(elem, size), Array(xs)) => {
      guard xs.length() == check_array_size(size) else {
        raise InvalidValue(
          "\{t.name()} needs \{size} elements, got \{xs.length()}",
        )
      }
      encode_block(Array::make(size, elem), xs)
    }
    (Tuple(elems), Tuple(vs)) => encode_block(elems, vs)
    _ => raise InvalidValue("\{v} is not a \{t.name()}")
  }
}
