///|
/// The contract every prepared call below points at.
fn prepared_address() -> @types.Address {
  @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7") catch {
    e => abort("bad test address: \{e}")
  }
}

///|
test "preparing a call encodes it and sends nothing" {
  let contract = @contract.Contract::new(prepared_address())
  let prepared = contract.prepare(name="test")
  inspect(
    prepared.target(),
    content="0x52908400098527886E0F7030069857D2E4169EE7",
  )
  // the same calldata `Contract::call` puts on the wire — `test()`
  inspect(prepared.data(), content="0xf8a8fd6d")
}

///|
test "arguments are encoded behind the selector" {
  let contract = @contract.Contract::new(prepared_address())
  let prepared = contract.prepare(
    name="balanceOf",
    inputs=[Address],
    args=[Address(prepared_address())],
    outputs=[Uint(256)],
  )
  inspect(
    prepared.data(),
    content="0x70a08231" +
      "00000000000000000000000052908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
test "a call that cannot be encoded is an Abi failure, not a request" {
  let contract = @contract.Contract::new(prepared_address())
  try
    contract.prepare(name="test", inputs=[Uint(256)], args=[]) |> ignore
  catch {
    @contract.ContractError::Abi(_) => ()
    e => fail("expected an ABI failure, not \{e}")
  } noraise {
    _ => fail("expected the mismatch to raise")
  }
}

///|
test "decode reads return data as the outputs the call declared" {
  let contract = @contract.Contract::new(prepared_address())
  let prepared = contract.prepare(name="answer", outputs=[Uint(256)])
  let answer = @types.Hex::from_string(
    "0x00000000000000000000000000000000000000000000000000000000000003e8",
  ) catch {
    e => abort("bad test data: \{e}")
  }
  debug_inspect(prepared.decode(answer), content="[Uint(1000)]")
  // and data that does not fit them is the ABI's failure
  let short = @types.Hex::from_string("0x03e8") catch {
    e => abort("bad test data: \{e}")
  }
  try prepared.decode(short) |> ignore catch {
    @contract.ContractError::Abi(_) => ()
    e => fail("expected an ABI failure, not \{e}")
  } noraise {
    _ => fail("expected the short answer to raise")
  }
}

///|
test "revert reads raw bytes with the contract's own declarations" {
  let contract = @contract.Contract::new(prepared_address(), errors=[
    insufficient_balance(),
  ])
  let prepared = contract.prepare(name="transfer")
  // a string reason, which needs no declaration
  inspect(
    prepared.revert(hex_of(revert_data("Error", [String], [String("nope")]))),
    content="Revert(nope)",
  )
  // a custom error, which does — and the prepared call carried it along
  inspect(
    prepared.revert(hex_of(insufficient_balance_data())),
    content="CustomError(InsufficientBalance(Uint(100), Uint(200)))",
  )
  // and one nothing declares still names itself by selector
  let unknown = revert_data("Unknown", [Uint(256)], [Uint(1N)])
  inspect(
    prepared.revert(hex_of(unknown)) is CustomError(name=None, ..),
    content="true",
  )
}

///|
test "a prepared call with no declarations leaves a custom error encoded" {
  let contract = @contract.Contract::new(prepared_address())
  let prepared = contract.prepare(name="transfer")
  inspect(
    prepared.revert(hex_of(insufficient_balance_data())),
    content="CustomError(0xcf479181)",
  )
}

///|
/// `revert_test.mbt` builds its revert bytes as strings, since that is what a
/// `ProviderError` carries; a prepared call takes the `Hex` itself.
fn hex_of(digits : String) -> @types.Hex {
  @types.Hex::from_string(digits) catch {
    e => abort("bad test data: \{e}")
  }
}
