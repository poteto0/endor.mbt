///|
test "static values each take one word" {
  inspect(
    encoded([Uint(256), Uint(8), Bool, Bool, Address], [
      Uint(69N),
      Uint(255N),
      Bool(true),
      Bool(false),
      Address(dead()),
    ]),
    content="0x" +
      word("45") +
      word("ff") +
      word("1") +
      word("0") +
      word("dead"),
  )
}

///|
/// Negative numbers are two's complement over the whole 32-byte word, so `-1`
/// is all ones however narrow the declared type is.
test "signed values are two's complement" {
  inspect(
    encoded([Int(256), Int(8), Int(256)], [Int(-1N), Int(-128N), Int(42N)]),
    content="0x" +
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80" +
      word("2a"),
  )
}

///|
/// `bytesN` is left-aligned in its word, unlike every number.
test "fixed bytes are left-aligned" {
  inspect(
    encoded([FixedBytes(3), FixedBytes(32)], [
      Bytes(b"abc"),
      Bytes(Bytes::makei(32, _ => b'\xff')),
    ]),
    content="0x" +
      "6162630000000000000000000000000000000000000000000000000000000000" +
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  )
}

///|
/// The `sam(bytes,bool,uint256[])` example from the ABI specification: two
/// dynamic arguments around a static one, so the heads are offset, value,
/// offset, and the tails follow in that order.
test "dynamic values are written as offsets into the tail" {
  inspect(
    encoded([Bytes, Bool, Array(Uint(256))], [
      Bytes(b"dave"),
      Bool(true),
      Array([Uint(1N), Uint(2N), Uint(3N)]),
    ]),
    content="0x" +
      word("60") +
      word("1") +
      word("a0") +
      word("4") +
      "6461766500000000000000000000000000000000000000000000000000000000" +
      word("3") +
      word("1") +
      word("2") +
      word("3"),
  )
}

///|
/// The `f(uint256,uint32[],bytes10,bytes)` example from the same section: the
/// two static arguments sit in the head between the two offsets.
test "static and dynamic arguments interleave" {
  let data = @abi.encode_call(
    name="f",
    inputs=[Uint(256), Array(Uint(32)), FixedBytes(10), Bytes],
    args=[
      Uint(0x123N),
      Array([Uint(0x456N), Uint(0x789N)]),
      Bytes(b"1234567890"),
      Bytes(b"Hello, world!"),
    ],
  ) catch {
    e => abort("unexpected error: \{e}")
  }
  inspect(
    data,
    content="0x8be65246" +
      word("123") +
      word("80") +
      "3132333435363738393000000000000000000000000000000000000000000000" +
      word("e0") +
      word("2") +
      word("456") +
      word("789") +
      word("d") +
      "48656c6c6f2c20776f726c642100000000000000000000000000000000000000",
  )
}

///|
/// A fixed-length array of a static type is written inline, with no length and
/// no offset — the type already says how many there are.
test "a fixed array of static elements is inline" {
  inspect(
    encoded([FixedArray(FixedBytes(3), 2)], [
      Array([Bytes(b"abc"), Bytes(b"def")]),
    ]),
    content="0x" +
      "6162630000000000000000000000000000000000000000000000000000000000" +
      "6465660000000000000000000000000000000000000000000000000000000000",
  )
}

///|
/// A tuple is what a `struct` is on the wire: a static one flattens into the
/// head, taking as many words as it has members.
test "a static tuple flattens into the head" {
  inspect(
    encoded([Tuple([Uint(256), Bool]), Uint(8)], [
      Tuple([Uint(7N), Bool(true)]),
      Uint(9N),
    ]),
    content="0x" + word("7") + word("1") + word("9"),
  )
}

///|
/// One dynamic member makes the whole tuple dynamic, so it moves to the tail
/// and leaves an offset behind.
test "a tuple with a dynamic member is itself dynamic" {
  inspect(
    encoded([Tuple([Uint(256), String]), Uint(8)], [
      Tuple([Uint(7N), String("hi")]),
      Uint(9N),
    ]),
    content="0x" +
      word("40") +
      word("9") +
      word("7") +
      word("40") +
      word("2") +
      "6869000000000000000000000000000000000000000000000000000000000000",
  )
}

///|
/// An empty dynamic value is a length of zero and nothing else — there is no
/// partial word to pad out.
test "empty dynamic values are just their length" {
  inspect(
    encoded([Bytes, Array(Uint(256))], [Bytes(b""), Array([])]),
    content="0x" + word("40") + word("60") + word("0") + word("0"),
  )
  inspect(encoded([], []), content="0x")
}

///|
/// `string` is `bytes` with an encoding attached.
test "strings are encoded as their UTF-8 bytes" {
  inspect(
    encoded([String], [String("héllo")]),
    content="0x" +
      word("20") +
      word("6") +
      "68c3a96c6c6f0000000000000000000000000000000000000000000000000000",
  )
}

///|
test "a value that does not fit its type is refused" {
  inspect(
    refused(() => encode_ignoring([Uint(8)], [Uint(256N)])),
    content=(
      #|InvalidValue("uint8 cannot hold 256")
    ),
  )
  inspect(
    refused(() => encode_ignoring([Uint(256)], [Uint(-1N)])),
    content=(
      #|InvalidValue("uint256 cannot hold -1")
    ),
  )
  inspect(
    refused(() => encode_ignoring([Int(8)], [Int(128N)])),
    content=(
      #|InvalidValue("int8 cannot hold 128")
    ),
  )
  inspect(
    refused(() => encode_ignoring([FixedBytes(4)], [Bytes(b"abc")])),
    content=(
      #|InvalidValue("bytes4 needs 4 bytes, got 3")
    ),
  )
  inspect(
    refused(() => {
      encode_ignoring([FixedArray(Uint(256), 2)], [Array([Uint(1N)])])
    }),
    content=(
      #|InvalidValue("uint256[2] needs 2 elements, got 1")
    ),
  )
}

///|
test "a value of the wrong shape is refused" {
  inspect(
    refused(() => encode_ignoring([Address], [Uint(1N)])),
    content=(
      #|InvalidValue("Uint(1) is not a address")
    ),
  )
  inspect(
    refused(() => encode_ignoring([Uint(256), Bool], [Uint(1N)])),
    content=(
      #|InvalidValue("expected 2 values, got 1")
    ),
  )
}

///|
/// `encode` for the tests that only care that it raised.
fn encode_ignoring(
  types : Array[@abi.AbiType],
  values : Array[@abi.AbiValue],
) -> Unit raise @abi.AbiError {
  @abi.encode(types, values) |> ignore
}

///|
/// A payload far wider than the small cases above: several thousand words, and
/// a byte string of a few hundred KB. Both go down the path that no longer
/// detours through `Bytes`, so both are pinned to the length and the digits the
/// layout calls for.
test "a large value encodes to what its layout says" {
  let n = 4_000
  let xs : Array[@abi.AbiValue] = []
  for i in 0..<n {
    xs.push(Uint(BigInt::from_int(i)))
  }
  let data = @abi.encode([Array(Uint(256))], [Array(xs)]).to_string()
  // an offset word, a length word, then one word per element
  assert_eq(data.length(), 2 + (2 + n) * 64)
  assert_eq(data[2:130].to_owned(), word("20") + word("fa0"))
  // the last element is 3999 == 0xf9f
  assert_eq(data[data.length() - 64:].to_owned(), word("f9f"))
}

///|
/// The same size, through `bytes` rather than an array: what comes back out has
/// to be what went in, byte for byte.
test "a large byte string survives encode and decode" {
  let blob = Bytes::makei(128_007, i => (i % 251).to_byte())
  let packed = @abi.encode([Bytes], [Bytes(blob)])
  assert_eq(@abi.decode([Bytes], packed), [Bytes(blob)])
}
