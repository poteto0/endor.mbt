///|
/// What a mock cannot prove about a revert: that a real node hands the data back
/// at all, and where in its JSON-RPC error it puts it.
///
/// Every decoding step below is unit-tested in `contract/revert_test.mbt`. Only
/// `error.data` is left, and it is the step the standards leave open.

///|
/// `require(cond, "…")`, which is `Error(string)`.
async test "a revert with a reason comes back as the reason" {
  @anvil.on(provider => {
    let at = @anvil.deploy_reverter(provider, revert_data=error_string("nope"))
    try
      @contract.Contract::new(at).call(provider, name="poke") |> ignore
    catch {
      e => inspect(e, content="Revert(nope)")
    } noraise {
      _ => fail("the reverter answered a call")
    }
  })
}

///|
/// A compiler check that failed: `Panic(uint256)` with 0x11, the overflow.
async test "a panic comes back as the bug it is" {
  @anvil.on(provider => {
    let data = @abi.encode_call(name="Panic", inputs=[Uint(256)], args=[
      Uint(0x11N),
    ])
    let at = @anvil.deploy_reverter(provider, revert_data=data)
    try
      @contract.Contract::new(at).call(provider, name="poke") |> ignore
    catch {
      e => inspect(e, content="Panic(17: arithmetic overflow or underflow)")
    } noraise {
      _ => fail("the reverter answered a call")
    }
  })
}

///|
/// A custom error, with and without the declaration that names it: the same
/// revert off the same node, read twice.
async test "a custom error is decoded when the contract declares it" {
  @anvil.on(provider => {
    let declared : @contract.ErrorDef = {
      name: "InsufficientBalance",
      inputs: [Uint(256), Uint(256)],
    }
    let data = @abi.encode_call(
      name="InsufficientBalance",
      inputs=[Uint(256), Uint(256)],
      args=[Uint(100N), Uint(200N)],
    )
    let at = @anvil.deploy_reverter(provider, revert_data=data)
    try
      @contract.Contract::new(at, errors=[declared]).call(provider, name="poke")
      |> ignore
    catch {
      e =>
        inspect(
          e,
          content="CustomError(InsufficientBalance(Uint(100), Uint(200)))",
        )
    } noraise {
      _ => fail("the reverter answered a call")
    }
    // and without it, the selector is still what the node sent
    try
      @contract.Contract::new(at).call(provider, name="poke") |> ignore
    catch {
      e => inspect(e, content="CustomError(\{declared.selector().unwrap()})")
    } noraise {
      _ => fail("the reverter answered a call")
    }
  })
}

///|
/// The other call that runs the contract without mining anything:
/// `eth_estimateGas`, which is where a wallet finds out that the transaction it
/// is about to prompt for would revert.
///
/// A plain RPC helper, so the revert arrives as `ProviderError::Reverted` with
/// the data still encoded. A bare node has no such stage for a send.
async test "estimating gas for a call that reverts carries the revert" {
  @anvil.on(provider => {
    let at = @anvil.deploy_reverter(provider, revert_data=error_string("nope"))
    try
      @provider.estimate_gas(
        provider,
        @types.CallRequest::new(at, from=@anvil.dev_account()),
      )
      |> ignore
    catch {
      e => assert_true(e is Reverted(data~, ..) && data == error_string("nope"))
    } noraise {
      _ => fail("estimating gas for a reverting call answered")
    }
  })
}

///|
/// `REVERT(0, 0)` — a `require` with no message — has nothing to decode, so it
/// stays what the node said rather than becoming an invented reason.
async test "a revert with no data stays what the node said" {
  @anvil.on(provider => {
    let gate = @anvil.deploy_selector_gate(
      provider,
      @abi.selector("balanceOf(address)"),
    )
    try
      @contract.Contract::new(gate).call(provider, name="totalSupply") |> ignore
    catch {
      e => assert_true(e is Rpc(_))
    } noraise {
      _ => fail("the gate answered a selector it was not deployed for")
    }
  })
}

///|
/// The revert `revert("…")` produces: `Error(string)` with one argument.
fn error_string(reason : String) -> @types.Hex {
  @abi.encode_call(name="Error", inputs=[String], args=[String(reason)]) catch {
    e => abort("bad revert data: \{e}")
  }
}
