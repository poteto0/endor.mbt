///|
/// A node's answer to a call the contract refused, carrying `data` as the
/// revert.
fn reverted(data : String) -> @provider.ProviderError {
  let data = @types.Hex::from_string(data) catch {
    e => abort("bad revert data: \{e}")
  }
  @provider.Reverted(code=3, message="execution reverted", data~)
}

///|
/// A revert, as the encoder builds one: an error's name and arguments are
/// encoded exactly as a call's are, which is why `@abi.encode_call` writes both.
fn revert_data(
  name : String,
  inputs : Array[@abi.AbiType],
  args : Array[@abi.AbiValue],
) -> String {
  (@abi.encode_call(name~, inputs~, args~) catch {
    e => abort("bad revert data: \{e}")
  }).to_string()
}

///|
/// `error InsufficientBalance(uint256 have, uint256 want)`.
fn insufficient_balance() -> @contract.ErrorDef {
  { name: "InsufficientBalance", inputs: [Uint(256), Uint(256)] }
}

///|
/// The revert `error InsufficientBalance(100, 200)` produces.
fn insufficient_balance_data() -> String {
  revert_data("InsufficientBalance", [Uint(256), Uint(256)], [
    Uint(100N),
    Uint(200N),
  ])
}

///|
/// The two selectors every Solidity contract shares are compared against
/// constants rather than hashed per revert, so what they are is pinned here.
test "the built-in revert selectors are what the ABI hashes them to" {
  inspect(@abi.selector("Error(string)"), content="0x08c379a0")
  inspect(@abi.selector("Panic(uint256)"), content="0x4e487b71")
}

///|
test "Error(string) is decoded into its reason" {
  let data = revert_data("Error", [String], [String("nope")])
  inspect(@contract.revert_error(reverted(data)), content="Revert(nope)")
  // and the bytes really are what a node sends: selector, offset, length, text
  inspect(
    data,
    content="0x08c379a0" +
      "0000000000000000000000000000000000000000000000000000000000000020" +
      "0000000000000000000000000000000000000000000000000000000000000004" +
      "6e6f706500000000000000000000000000000000000000000000000000000000",
  )
}

///|
test "Panic(uint256) is decoded with what the code means" {
  let overflow = revert_data("Panic", [Uint(256)], [Uint(0x11N)])
  inspect(
    @contract.revert_error(reverted(overflow)),
    content="Panic(17: arithmetic overflow or underflow)",
  )
  let unknown = revert_data("Panic", [Uint(256)], [Uint(0x99N)])
  inspect(
    @contract.revert_error(reverted(unknown)),
    content="Panic(153: unknown panic code)",
  )
  // a code no byte can hold is unknown by the same rule, and does not wrap
  // around onto one that is known
  let huge = revert_data("Panic", [Uint(256)], [Uint(0x1_0000_0011N)])
  inspect(
    @contract.revert_error(reverted(huge)),
    content="Panic(4294967313: unknown panic code)",
  )
}

///|
test "a custom error keeps its selector and data when nothing declares it" {
  let e = @contract.revert_error(reverted(insufficient_balance_data()))
  inspect(e, content="CustomError(0xcf479181)")
  guard e is CustomError(name~, args~, data~, ..) else {
    fail("expected a custom error, got \{e}")
  }
  assert_eq(name, None)
  assert_eq(args, [])
  assert_eq(data.to_string(), insufficient_balance_data())
}

///|
test "a declared custom error is decoded down to its arguments" {
  let e = @contract.revert_error(reverted(insufficient_balance_data()), errors=[
    insufficient_balance(),
  ])
  inspect(e, content="CustomError(InsufficientBalance(Uint(100), Uint(200)))")
  guard e is CustomError(name~, args~, ..) else {
    fail("expected a custom error, got \{e}")
  }
  assert_eq(name, Some("InsufficientBalance"))
  assert_eq(args, [Uint(100N), Uint(200N)])
}

///|
test "a definition that does not match is not tried" {
  let other : @contract.ErrorDef = { name: "Unauthorized", inputs: [Address] }
  inspect(
    @contract.revert_error(reverted(insufficient_balance_data()), errors=[other]),
    content="CustomError(0xcf479181)",
  )
}

///|
test "a definition naming a width that cannot exist has no selector" {
  let impossible : @contract.ErrorDef = { name: "Nope", inputs: [Uint(7)] }
  assert_eq(impossible.selector(), None)
  // and so it matches nothing rather than stopping the search
  inspect(
    @contract.revert_error(reverted(insufficient_balance_data()), errors=[
      impossible,
      insufficient_balance(),
    ]),
    content="CustomError(InsufficientBalance(Uint(100), Uint(200)))",
  )
}

///|
test "a revert with nothing in it stays what the wallet said" {
  // `require(cond)` with no message at all
  inspect(
    @contract.revert_error(reverted("0x")),
    content=(
      #|Rpc(Reverted(code=3, message="execution reverted", data=0x))
    ),
  )
  // and a `data` too short to name anything
  inspect(
    @contract.revert_error(reverted("0x08c3")),
    content=(
      #|Rpc(Reverted(code=3, message="execution reverted", data=0x08c3))
    ),
  )
}

///|
test "data that does not fit the error it names keeps its selector" {
  // `Error(string)` whose payload is one word too short to hold a string
  let truncated = "0x08c379a0" +
    "0000000000000000000000000000000000000000000000000000000000000020"
  inspect(
    @contract.revert_error(reverted(truncated)),
    content="CustomError(0x08c379a0)",
  )
}

///|
test "anything that is not a revert is untouched" {
  inspect(
    @contract.revert_error(@provider.UserRejected),
    content="Rpc(UserRejected)",
  )
  inspect(
    @contract.revert_error(@provider.Rpc(code=-32603, message="boom")),
    content=(
      #|Rpc(Rpc(code=-32603, message="boom"))
    ),
  )
}

///|
async test "a call that reverts raises the reason the contract gave" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_call",
      error=reverted(insufficient_balance_data()),
    )
    let contract = @contract.Contract::new(test_address(), errors=[
      insufficient_balance(),
    ])
    try
      contract.call(provider, name="withdraw", outputs=[Uint(256)]) |> ignore
    catch {
      e =>
        inspect(
          e,
          content="CustomError(InsufficientBalance(Uint(100), Uint(200)))",
        )
    } noraise {
      _ => fail("expected the call to raise")
    }
  })
}

///|
async test "a transaction the wallet refused carries the revert too" {
  @async.with_task_group(_ => {
    let data = revert_data("Error", [String], [String("nope")])
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_sendTransaction",
      error=reverted(data),
    )
    let contract = @contract.Contract::new(test_address())
    try
      contract.send(provider, from=test_address(), name="withdraw") |> ignore
    catch {
      e => inspect(e, content="Revert(nope)")
    } noraise {
      _ => fail("expected the transaction to raise")
    }
  })
}
