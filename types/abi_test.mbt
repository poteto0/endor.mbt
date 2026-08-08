///|
/// The canonical names, checked here rather than only through `@abi.signature`:
/// this is where the spelling — and the validation it does on the way — lives.
test "AbiType::name spells the ABI's own type names" {
  inspect(name(Uint(256)), content="uint256")
  inspect(name(Int(8)), content="int8")
  inspect(name(FixedBytes(32)), content="bytes32")
  inspect(name(Array(Tuple([Address, Bool]))), content="(address,bool)[]")
  inspect(name(FixedArray(Bytes, 0)), content="bytes[0]")
}

///|
/// `AbiType::name`, where raising would be this test's own bug.
fn name(t : @types.AbiType) -> String {
  t.name() catch {
    e => abort("unexpected error: \{e}")
  }
}

///|
/// The error a call raised, as text — not raising is itself an answer, so it
/// shows up in the diff rather than aborting the run.
fn refused(f : () -> Unit raise @types.AbiError) -> String {
  try {
    f()
    "no error"
  } catch {
    e => "\{e}"
  }
}

///|
/// A type that cannot appear in an ABI has no canonical name, and says so as an
/// `AbiError` — the same error `@abi.encode` raises, since it is the same rule
/// being checked one layer down.
test "the width and size rules refuse a type no contract can declare" {
  inspect(
    refused(() => @types.AbiType::Uint(7).name() |> ignore),
    content=(
      #|InvalidAbiType("uint7: width must be a multiple of 8 in 8..=256")
    ),
  )
  inspect(
    refused(() => @types.AbiType::Int(512).name() |> ignore),
    content=(
      #|InvalidAbiType("int512: width must be a multiple of 8 in 8..=256")
    ),
  )
  inspect(
    refused(() => @types.AbiType::FixedBytes(0).name() |> ignore),
    content=(
      #|InvalidAbiType("bytes0: size must be in 1..=32")
    ),
  )
  inspect(
    refused(() => @types.AbiType::FixedArray(Bool, -1).name() |> ignore),
    content=(
      #|InvalidAbiType("T[-1]: length cannot be negative")
    ),
  )
}

///|
/// What a width holds, which is the rule `@abi.encode` checks a value against
/// and EIP-712 checks a document's numbers against.
test "a value is refused by the width it does not fit" {
  inspect(
    refused(() => @types.AbiValue::checked_uint(256N, bits=8) |> ignore),
    content=(
      #|InvalidValue("uint8 cannot hold 256")
    ),
  )
  inspect(
    refused(() => @types.AbiValue::checked_uint(-1N, bits=256) |> ignore),
    content=(
      #|InvalidValue("uint256 cannot hold -1")
    ),
  )
  inspect(
    refused(() => @types.AbiValue::checked_int(128N, bits=8) |> ignore),
    content=(
      #|InvalidValue("int8 cannot hold 128")
    ),
  )
  inspect(
    refused(() => @types.AbiValue::checked_int(-129N, bits=8) |> ignore),
    content=(
      #|InvalidValue("int8 cannot hold -129")
    ),
  )
  // the widths themselves are checked first: `uint7` is wrong about the type,
  // not about the value
  inspect(
    refused(() => @types.AbiValue::checked_uint(1N, bits=7) |> ignore),
    content=(
      #|InvalidAbiType("uint7: width must be a multiple of 8 in 8..=256")
    ),
  )
}

///|
/// The bounds hold: two's complement is one wider below zero than above.
test "a value the width holds comes back unchanged" {
  assert_eq(@types.AbiValue::checked_uint(255N, bits=8), 255N)
  assert_eq(@types.AbiValue::checked_uint(0N, bits=8), 0N)
  assert_eq(@types.AbiValue::checked_int(127N, bits=8), 127N)
  assert_eq(@types.AbiValue::checked_int(-128N, bits=8), -128N)
}
