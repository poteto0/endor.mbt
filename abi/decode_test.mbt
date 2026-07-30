///|
/// `decode` for the tests that only care that it raised.
fn decode_ignoring(
  types : Array[@abi.AbiType],
  data : String,
) -> Unit raise @abi.AbiError {
  let hex = @types.Hex::from_string(data) catch {
    e => abort("bad test data: \{e}")
  }
  @abi.decode(types, hex) |> ignore
}

///|
/// What a `uint256` getter answers — one word, the whole return data.
test "a single static value is one word" {
  inspect(decoded([Uint(256)], "0x" + word("2a")), content="[Uint(42)]")
  inspect(
    decoded([Bool, Bool], "0x" + word("1") + word("0")),
    content="[Bool(true), Bool(false)]",
  )
  inspect(
    decoded([Address], "0x" + word("dead")),
    content=(
      #|[Address({ inner: "0x000000000000000000000000000000000000dead" })]
    ),
  )
}

///|
/// The sign lives in the top bit of the word, whatever the declared width, so
/// reading it back is the same shift for `int8` and `int256`.
test "signed values come back negative" {
  inspect(
    decoded(
      [Int(256), Int(8)],
      "0x" +
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80",
    ),
    content="[Int(-1), Int(-128)]",
  )
}

///|
test "fixed bytes are the leading bytes of the word" {
  inspect(
    decoded(
      [FixedBytes(3)],
      "0x6162630000000000000000000000000000000000000000000000000000000000",
    ),
    content="[Bytes(<Bytes: [0x61, 0x62, 0x63]>)]",
  )
}

///|
/// The `sam(bytes,bool,uint256[])` encoding read back — offsets followed to
/// the tail and the elements counted out of it.
test "dynamic values are read through their offsets" {
  inspect(
    decoded(
      [Bytes, Bool, Array(Uint(256))],
      "0x" +
      word("60") +
      word("1") +
      word("a0") +
      word("4") +
      "6461766500000000000000000000000000000000000000000000000000000000" +
      word("3") +
      word("1") +
      word("2") +
      word("3"),
    ),
    content=(
      #|[
      #|  Bytes(<Bytes: [0x64, 0x61, 0x76, 0x65]>),
      #|  Bool(true),
      #|  Array([Uint(1), Uint(2), Uint(3)]),
      #|]
    ),
  )
}

///|
test "strings come back from their UTF-8 bytes" {
  inspect(
    decoded(
      [String],
      "0x" +
      word("20") +
      word("6") +
      "68c3a96c6c6f0000000000000000000000000000000000000000000000000000",
    ),
    content=(
      #|[String("héllo")]
    ),
  )
}

///|
/// Round-tripping is the property that matters most: whatever `encode` lays
/// out, `decode` reads back as the values that went in — here through two
/// levels of nesting, where every offset is relative to its own block.
test "nested values round-trip" {
  let types : Array[@abi.AbiType] = [
    Array(Array(Uint(256))),
    Array(String),
    Tuple([Address, FixedArray(Bool, 2), Bytes]),
  ]
  let values : Array[@abi.AbiValue] = [
    Array([Array([Uint(1N), Uint(2N)]), Array([Uint(3N)])]),
    Array([String("one"), String("two"), String("three")]),
    Tuple([
      Address(dead()),
      Array([Bool(true), Bool(false)]),
      Bytes(b"\x01\x02\x03"),
    ]),
  ]
  assert_eq(decoded(types, encoded(types, values)), @debug.to_string(values))
}

///|
/// Return data that stops short is a contract that did not answer what its ABI
/// promised, so it raises rather than reading a half word as a value.
test "data that does not fit the types is refused" {
  inspect(
    refused(() => decode_ignoring([Uint(256), Uint(256)], "0x" + word("1"))),
    content="InvalidData(expected a word at byte 32, but the data is 32 bytes)",
  )
  inspect(
    refused(() => decode_ignoring([Uint(256)], "0x")),
    content="InvalidData(expected a word at byte 0, but the data is 0 bytes)",
  )
  inspect(
    refused(() => decode_ignoring([Bool], "0x" + word("2"))),
    content="InvalidData(bool must be 0 or 1, got 2)",
  )
}

///|
/// An offset or a length can say anything at all, so neither is trusted: both
/// are checked against the data actually in hand before being indexed with.
test "an offset or length outside the data is refused" {
  inspect(
    refused(() => decode_ignoring([Bytes], "0x" + word("80") + word("0"))),
    content="InvalidData(offset 128 is past the end of 64 bytes)",
  )
  inspect(
    refused(() => decode_ignoring([Bytes], "0x" + word("20") + word("40"))),
    content="InvalidData(64 bytes claimed at byte 64, past the end of 64 bytes)",
  )
  inspect(
    refused(() => {
      decode_ignoring(
        [Bytes],
        "0x" +
        word("20") +
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
    }),
    content="InvalidData(byte length is far larger than the data)",
  )
}

///|
test "invalid utf-8 string is refused" {
  inspect(
    refused(() => {
      ignore(
        decode_ignoring(
          [String],
          "0x" +
          word("20") +
          word("1") +
          "8000000000000000000000000000000000000000000000000000000000000000",
        ),
      )
    }),
    content="InvalidData(string is not valid UTF-8)",
  )
}

///|
test "error on invalid value" {
  inspect(
    refused(() => {
      decode_ignoring(
        [Uint(8)],
        "0x00000000000000000000000000000000000000000000000000000000000001ff",
      )
    }),
    content="InvalidData(Uint(8) encoding)",
  )
  inspect(
    refused(() => {
      decode_ignoring(
        [Int(8)],
        "0x00000000000000000000000000000000000000000000000000000000000000c8",
      )
    }),
    content="InvalidData(Int(8) encoding)",
  )
  inspect(
    refused(() => {
      decode_ignoring(
        [Address],
        "0xdeadbeefdeadbeefdeadbeefdeadbeef00000000000000000000000000000001",
      )
    }),
    content="InvalidData(Address encoding)",
  )
  inspect(
    refused(() => {
      decode_ignoring(
        [FixedBytes(1)],
        "0x1111111111111111111111111111111111111111111111111111111111111111",
      )
    }),
    content="InvalidData(FixedBytes(1) encoding)",
  )
}
