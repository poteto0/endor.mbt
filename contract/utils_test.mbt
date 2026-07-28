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
