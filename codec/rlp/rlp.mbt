///|
/// A value in the shape RLP can encode.
///
/// RLP knows a run of bytes and a list of items, and nothing else: position
/// alone says what a value means. Open, because an item has no invalid form —
/// the rule that a number carries no leading zeros belongs to the number, so it
/// lives in `Item::of_uint64` and `Item::of_bigint`.
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
    let width = length_width(length)
    out.push((offset + 55 + width).to_byte())
    for i = width - 1; i >= 0; i = i - 1 {
      out.push((length >> (i * 8)).to_byte())
    }
  }
}

///|
/// How many bytes it takes to spell `value` — none at all for zero, which is
/// what makes RLP write it as the empty string.
///
/// Counting first and writing once keeps a small number cheap: eight bytes then
/// trim allocates twice, and on `js` those shifts are `BigInt` arithmetic.
fn byte_width(value : UInt64) -> Int {
  let mut width = 0
  let mut left = value
  while left != 0UL {
    width = width + 1
    left = left >> 8
  }
  width
}

///|
/// The same count for a length rather than a value. Separate because a length
/// is a machine word on every backend, while `UInt64` is a `BigInt` on `js` —
/// widening one only to count its bytes is the arithmetic this avoids.
fn length_width(length : Int) -> Int {
  let mut width = 0
  let mut left = length
  while left != 0 {
    width = width + 1
    left = left >> 8
  }
  width
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
  let width = byte_width(value)
  Bytes(Bytes::makei(width, i => (value >> ((width - 1 - i) * 8)).to_byte()))
}

///|
/// The same rule for a number too wide for 64 bits — a `Wei` amount, or the
/// halves of a signature.
pub fn Item::of_bigint(value : @bigint.BigInt) -> Item {
  // `to_octets` with no length is already the minimal encoding; the one case
  // it does not give is zero, which it writes as a zero byte where RLP wants
  // nothing at all.
  if value.is_zero() {
    Bytes(b"")
  } else {
    Bytes(value.to_octets())
  }
}
