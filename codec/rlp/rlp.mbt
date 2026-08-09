///|
/// A value in the shape RLP can encode.
///
/// RLP knows two things and no others: a run of bytes, and a list of items.
/// There are no field names, no types and no lengths declared anywhere else —
/// position alone says what a value means, which is why every party has to
/// agree on the order of a transaction's fields to read one back.
///
/// Open, because an item has no invalid form: any bytes are a string, any
/// items are a list. The rule that *is* worth enforcing — that a number is
/// written without leading zeros — belongs to the number, so it lives in
/// `Item::of_uint64` and `Item::of_bigint` rather than in the type.
pub(all) enum Item {
  /// A run of bytes, encoded as itself with a length in front.
  Bytes(Bytes)
  /// A list, encoded as its items' encodings run together with a length in
  /// front. Nests to any depth.
  List(Array[Item])
} derive(Eq, Debug)

///|
/// The RLP encoding of an item.
///
/// ```
/// inspect(
///   @rlp.encode(List([Bytes(b"cat"), Bytes(b"dog")])),
///   content=
///     #|b"\xc8\x83\x63\x61\x74\x83\x64\x6f\x67"
///   ,
/// )
/// ```
pub fn encode(item : Item) -> Bytes {
  let out = []
  write(out, item)
  Bytes::from_array(out)
}

///|
fn write(out : Array[Byte], item : Item) -> Unit {
  match item {
    // A single byte below 0x80 is its own encoding — the one case with no
    // header, and what keeps small numbers one byte wide.
    Bytes([byte]) if byte < b'\x80' => out.push(byte)
    Bytes(bytes) => {
      write_header(out, bytes.length(), 0x80)
      for byte in bytes {
        out.push(byte)
      }
    }
    List(items) => {
      // The header carries the payload's length, so the payload has to be
      // encoded before anything can be written in front of it.
      let payload = []
      for item in items {
        write(payload, item)
      }
      write_header(out, payload.length(), 0xc0)
      for byte in payload {
        out.push(byte)
      }
    }
  }
}

///|
/// The length prefix, in whichever of the two forms fits: the length itself
/// added to `offset`, or — past what a single byte can carry — the length
/// written out and its own width added to `offset + 55`.
fn write_header(out : Array[Byte], length : Int, offset : Int) -> Unit {
  if length <= 55 {
    out.push((offset + length).to_byte())
  } else {
    let written = trim(big_endian(length.to_uint64()))
    out.push((offset + 55 + written.length()).to_byte())
    out.append(written)
  }
}

///|
fn big_endian(value : UInt64) -> Array[Byte] {
  let out = []
  for shift = 56; shift >= 0; shift = shift - 8 {
    out.push((value >> shift).to_byte())
  }
  out
}

///|
/// Drop leading zeros. RLP writes a number in the fewest bytes that spell it,
/// so that one number has one encoding: allowing `0x0001` beside `0x01` would
/// give a transaction two hashes.
fn trim(bytes : Array[Byte]) -> Array[Byte] {
  let mut start = 0
  while start < bytes.length() && bytes[start] == b'\x00' {
    start = start + 1
  }
  bytes[start:].to_owned()
}

///|
/// A number as RLP writes one: big-endian in the fewest bytes, and zero as the
/// empty string rather than a zero byte.
///
/// ```
/// inspect(
///   @rlp.encode(@rlp.Item::of_uint64(1024)),
///   content=
///     #|b"\x82\x04\x00"
///   ,
/// )
/// ```
pub fn Item::of_uint64(value : UInt64) -> Item {
  Bytes(Bytes::from_array(trim(big_endian(value))))
}

///|
/// The same rule for a number too wide for 64 bits — a `Wei` amount, or the
/// halves of a signature.
pub fn Item::of_bigint(value : @bigint.BigInt) -> Item {
  Bytes(Bytes::from_array(trim(value.to_octets(length=32).to_array())))
}
