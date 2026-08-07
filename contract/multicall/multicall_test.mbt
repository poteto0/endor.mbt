///|
/// A token the batched reads are made against. Parsing it cannot fail, so the
/// tests spend no lines on a codec they are not exercising.
fn token() -> @types.Address {
  @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7") catch {
    e => abort("bad test address: \{e}")
  }
}

///|
/// Somewhere Multicall3 might be deployed that is not where it usually is.
fn elsewhere() -> @types.Address {
  @types.Address::from_string("0x8617E340B3D01FA5F11F306F4090FD50E238070D") catch {
    e => abort("bad test address: \{e}")
  }
}

///|
fn hex(digits : String) -> @types.Hex {
  @types.Hex::from_string(digits) catch {
    e => abort("bad test hex: \{e}")
  }
}

///|
/// What the node answers a batch with: `Result[]`, one `(success, returnData)`
/// per call, encoded exactly as the contract would.
fn results(entries : Array[(Bool, @types.Hex)]) -> Json {
  let values = entries.map(entry => {
    @abi.AbiValue::Tuple([Bool(entry.0), Bytes(entry.1.to_bytes())])
  })
  let encoded = @abi.encode([Array(Tuple([Bool, Bytes]))], [Array(values)]) catch {
    e => abort("bad test results: \{e}")
  }
  encoded.to_string().to_json()
}

///|
/// One 32-byte word holding `n`, which is what a `uint256` answer looks like.
fn word(n : BigInt) -> @types.Hex {
  @abi.encode([Uint(256)], [Uint(n)]) catch {
    e => abort("bad test word: \{e}")
  }
}

///|
/// A revert, as the encoder builds one: an error's name and arguments are
/// encoded exactly as a call's are.
fn revert_data(
  name : String,
  inputs : Array[@abi.AbiType],
  args : Array[@abi.AbiValue],
) -> @types.Hex {
  @abi.encode_call(name~, inputs~, args~) catch {
    e => abort("bad test revert: \{e}")
  }
}

///|
/// `error InsufficientBalance(uint256 have, uint256 want)`.
fn insufficient_balance() -> @contract.ErrorDef {
  { name: "InsufficientBalance", inputs: [Uint(256), Uint(256)] }
}

///|
async test "a batch of two reads is one eth_call, answered in order" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=results([(true, word(18N)), (true, word(1000N))]),
    )
    let erc20 = @contract.Contract::new(token())
    let outcomes = @multicall.Multicall3::new().aggregate3(provider, [
      @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
      @multicall.Call::new(
        erc20.prepare(
          name="balanceOf",
          inputs=[Address],
          args=[Address(token())],
          outputs=[Uint(256)],
        ),
      ),
    ])
    inspect(outcomes.length(), content="2")
    debug_inspect(outcomes[0].values(), content="[Uint(18)]")
    debug_inspect(outcomes[1].values(), content="[Uint(1000)]")
    // one round trip for both of them, and it went to the canonical address
    inspect(provider.calls().length(), content="1")
    guard provider.last_call() is Some((_, Array([Object(request), _]))) else {
      fail("expected one eth_call")
    }
    debug_inspect(
      request.get("to"),
      content=(
        #|Some(String("0xca11bde05977b3631167028862be2a173976ca11"))
      ),
    )
  })
}

///|
async test "a call that reverts is one Failed among the answers" {
  @async.with_task_group(_ => {
    let refused = revert_data("Error", [String], [String("nope")])
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=results([(true, word(18N)), (false, refused)]),
    )
    let erc20 = @contract.Contract::new(token())
    let outcomes = @multicall.Multicall3::new().aggregate3(provider, [
      @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
      @multicall.Call::new(erc20.prepare(name="answer", outputs=[Uint(256)])),
    ])
    debug_inspect(outcomes[0].values(), content="[Uint(18)]")
    inspect(outcomes[1], content="Failed(Revert(nope))")
    // and asking for its values is where it finally raises
    try outcomes[1].values() |> ignore catch {
      @contract.ContractError::Revert(reason) => inspect(reason, content="nope")
      e => fail("expected a revert, not \{e}")
    } noraise {
      _ => fail("expected the failure to be raised")
    }
  })
}

///|
async test "a custom error comes back decoded when the contract declared it" {
  @async.with_task_group(_ => {
    let refused = revert_data("InsufficientBalance", [Uint(256), Uint(256)], [
      Uint(100N),
      Uint(200N),
    ])
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=results([(false, refused)]),
    )
    let erc20 = @contract.Contract::new(token(), errors=[insufficient_balance()])
    let outcomes = @multicall.Multicall3::new().aggregate3(provider, [
      @multicall.Call::new(
        erc20.prepare(
          name="transfer",
          inputs=[Address, Uint(256)],
          args=[Address(token()), Uint(1N)],
          outputs=[Bool],
        ),
      ),
    ])
    inspect(
      outcomes[0],
      content="Failed(CustomError(InsufficientBalance(Uint(100), Uint(200))))",
    )
  })
}

///|
async test "return data that does not decode fails only its own element" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      // the first answered a word too short to be a `uint256`
      response=results([(true, hex("0x03e8")), (true, word(18N))]),
    )
    let erc20 = @contract.Contract::new(token())
    let outcomes = @multicall.Multicall3::new().aggregate3(provider, [
      @multicall.Call::new(erc20.prepare(name="answer", outputs=[Uint(256)])),
      @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
    ])
    inspect(outcomes[0] is Failed(Abi(_)), content="true")
    debug_inspect(outcomes[1].values(), content="[Uint(18)]")
  })
}

///|
async test "an empty batch answers without asking the node anything" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new()
    let outcomes = @multicall.Multicall3::new().aggregate3(provider, [])
    inspect(outcomes.length(), content="0")
    inspect(provider.calls().length(), content="0")
  })
}

///|
async test "a batch the node refuses raises" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on_error(
      method_name="eth_call",
      error=@provider.Reverted(
        code=3,
        message="execution reverted",
        data=revert_data("Error", [String], [String("Multicall3: call failed")]),
      ),
    )
    let erc20 = @contract.Contract::new(token())
    try
      @multicall.Multicall3::new().aggregate3(provider, [
        @multicall.Call::new(
          erc20.prepare(name="decimals", outputs=[Uint(8)]),
          allow_failure=false,
        ),
      ])
      |> ignore
    catch {
      @contract.ContractError::Revert(reason) =>
        inspect(reason, content="Multicall3: call failed")
      e => fail("expected the batch to revert, not \{e}")
    } noraise {
      _ => fail("expected the batch to raise")
    }
  })
}

///|
async test "is_deployed answers on the code at the address" {
  @async.with_task_group(_ => {
    let there = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x6080604052".to_json(),
    )
    inspect(@multicall.Multicall3::new().is_deployed(there), content="true")
    let nowhere = @provider.MockProvider::new().on(
      method_name="eth_getCode",
      response="0x".to_json(),
    )
    inspect(@multicall.Multicall3::new().is_deployed(nowhere), content="false")
  })
}

///|
async test "another deployment is the one the batch is sent to" {
  @async.with_task_group(_ => {
    let multicall = @multicall.Multicall3::new(address=elsewhere())
    inspect(
      multicall.address(),
      content="0x8617E340B3D01FA5F11F306F4090FD50E238070D",
    )
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=results([(true, word(18N))]),
    )
    let erc20 = @contract.Contract::new(token())
    let outcomes = multicall.aggregate3(
      provider,
      [@multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)]))],
      from=token(),
    )
    debug_inspect(outcomes[0].values(), content="[Uint(18)]")
    guard provider.last_call() is Some((_, Array([Object(request), _]))) else {
      fail("expected one eth_call")
    }
    debug_inspect(
      request.get("to"),
      content=(
        #|Some(String("0x8617e340b3d01fa5f11f306f4090fd50e238070d"))
      ),
    )
    debug_inspect(
      request.get("from"),
      content=(
        #|Some(String("0x52908400098527886e0f7030069857d2e4169ee7"))
      ),
    )
  })
}

///|
async test "an answer with the wrong number of results is the batch's failure" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_call",
      response=results([(true, word(18N))]),
    )
    let erc20 = @contract.Contract::new(token())
    try
      @multicall.Multicall3::new().aggregate3(provider, [
        @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
        @multicall.Call::new(erc20.prepare(name="answer", outputs=[Uint(256)])),
      ])
      |> ignore
    catch {
      @contract.ContractError::Abi(e) =>
        inspect(
          e,
          content="InvalidData(aggregate3 answered with 1 results for 2 calls)",
        )
      e => fail("expected an ABI failure, not \{e}")
    } noraise {
      _ => fail("expected the mismatch to raise")
    }
  })
}
