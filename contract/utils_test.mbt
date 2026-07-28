///|
test "can decode answer" {
  inspect(
    @contract.uint_answer([@abi.AbiValue::Uint(1)], what="test"),
    content="1",
  )
  inspect(
    @contract.string_answer([@abi.AbiValue::String("test")], what="test"),
    content="test",
  )
  inspect(
    @contract.int_answer([@abi.AbiValue::Int(-1)], what="test"),
    content="-1",
  )
  inspect(
    @contract.bool_answer([@abi.AbiValue::Bool(true)], what="test"),
    content="true",
  )
  inspect(
    @contract.address_answer(
      [@abi.AbiValue::Address(@types.Address::from_string(dead))],
      what="test",
    ),
    content="0x000000000000000000000000000000000000dEaD",
  )
}

///|
test "error on type miss-match" {
  try
    @contract.uint_answer([@abi.AbiValue::String("test")], what="test")
  catch {
    @contract.ContractError::Abi(_) => ()
    e => abort("expect abi error, but got \{e}")
  } noraise {
    _ => abort("expect failed, but success")
  }

  try @contract.string_answer([@abi.AbiValue::Uint(1)], what="test") catch {
    @contract.ContractError::Abi(_) => ()
    e => abort("expect abi error, but got \{e}")
  } noraise {
    _ => abort("expect failed, but success")
  }
}

///|
/// `uint` and `int` decode to different `AbiValue` variants, so reading one as
/// the other has to fail rather than quietly widen: a `uint256` above
/// `2^255` and a negative `int256` are the same 32 bytes on the wire, and only
/// the declared type tells them apart.
test "a signed answer and an unsigned one are not interchangeable" {
  try @contract.int_answer([@abi.AbiValue::Uint(1)], what="skew") catch {
    e =>
      inspect(
        e,
        content="Abi(InvalidData(skew() did not answer a signed number))",
      )
  } noraise {
    _ => fail("expected a uint answer to be refused as an int")
  }
  try @contract.uint_answer([@abi.AbiValue::Int(1)], what="skew") catch {
    e => inspect(e, content="Abi(InvalidData(skew() did not answer a number))")
  } noraise {
    _ => fail("expected an int answer to be refused as a uint")
  }
}

///|
/// The message names the getter, because the mistake it almost always reports
/// is an address that is not the contract the caller took it for — and which
/// getter came back wrong is the only clue to that in the error.
test "a wrong answer names the getter that was asked" {
  try @contract.bool_answer([@abi.AbiValue::Uint(1)], what="paused") catch {
    e =>
      inspect(e, content="Abi(InvalidData(paused() did not answer a boolean))")
  } noraise {
    _ => fail("expected a number to be refused as a boolean")
  }
  try @contract.address_answer([], what="owner") catch {
    e =>
      inspect(e, content="Abi(InvalidData(owner() did not answer an address))")
  } noraise {
    _ => fail("expected an empty answer to be refused")
  }
}

///|
/// Every helper reads *one* value. A contract that answered with two of the
/// right type still did not answer what a single-value getter promised, so the
/// arity is part of the guard rather than something the first element is
/// plucked out of.
test "an answer of the right type but the wrong arity is still wrong" {
  for values in [[@abi.AbiValue::Uint(1), @abi.AbiValue::Uint(2)], []] {
    try @contract.uint_answer(values, what="totalSupply") catch {
      e => assert_true(e is Abi(_))
    } noraise {
      _ => fail("expected \{values.length()} values to be refused")
    }
  }
  try
    @contract.string_answer(
      [@abi.AbiValue::String("a"), @abi.AbiValue::String("b")],
      what="name",
    )
  catch {
    e => assert_true(e is Abi(_))
  } noraise {
    _ => fail("expected two strings to be refused")
  }
}

///|
let dead : String = "0x000000000000000000000000000000000000dead"
