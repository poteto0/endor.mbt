///|
/// Polygon, as a dapp would describe it to a wallet that does not know it yet.
/// The codec behind it is covered in `types/`; here it is only a payload the
/// RPC layer has to pass through unchanged.
fn polygon_params() -> @types.ChainParams {
  @types.ChainParams::new(
    @types.ChainId::polygon(),
    chain_name="Polygon Mainnet",
    rpc_urls=["https://polygon-rpc.com"],
    native_currency=@types.NativeCurrency::new(name="POL", symbol="POL"),
    block_explorer_urls=["https://polygonscan.com"],
  )
}

///|
async test "can switch chain" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="wallet_switchEthereumChain",
      response=Json::null(),
    )

    @provider.switch_chain(provider, @types.ChainId::mainnet()) catch {
      e => fail("unexpected error \{e}")
    }

    // the chain id reaches the wallet as a hex quantity inside an object
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "wallet_switchEthereumChain",
        #|    Array([Object({ "chainId": String("0x1") })]),
        #|  ),
        #|)
      ),
    )
  })
}

///|
/// The wallet prompts the user, so a rejection is the expected failure and it
/// reaches the caller untouched.
async test "error switch chain rejected by user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="wallet_switchEthereumChain",
      error=@provider.ProviderError::UserRejected,
    )

    try @provider.switch_chain(provider, @types.ChainId::sepolia()) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
async test "can add chain" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="wallet_addEthereumChain",
      response=Json::null(),
    )
    let params = polygon_params()

    @provider.add_chain(provider, params) catch {
      e => fail("unexpected error \{e}")
    }

    // the whole EIP-3085 description reaches the wallet as one object
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "wallet_addEthereumChain",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "chainId": String("0x89"),
        #|            "chainName": String("Polygon Mainnet"),
        #|            "rpcUrls": Array([String("https://polygon-rpc.com")]),
        #|            "nativeCurrency": Object(
        #|              {
        #|                "name": String("POL"),
        #|                "symbol": String("POL"),
        #|                "decimals": Number(18),
        #|              },
        #|            ),
        #|            "blockExplorerUrls": Array([String("https://polygonscan.com")]),
        #|          },
        #|        ),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
async test "error add chain rejected by user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="wallet_addEthereumChain",
      error=@provider.ProviderError::UserRejected,
    )

    try @provider.add_chain(provider, polygon_params()) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The whole point of the composite: the wallet answers the first switch with
/// 4902, and the chain is added and switched to without the caller seeing any
/// of it.
async test "can switch to a chain the wallet has to learn first" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new()
      .on_sequence(method_name="wallet_switchEthereumChain", answers=[
        Raises(UnrecognizedChain),
        Answers(Json::null()),
      ])
      .on(method_name="wallet_addEthereumChain", response=Json::null())
    let params = polygon_params()

    @provider.switch_or_add_chain(provider, params) catch {
      e => fail("unexpected error \{e}")
    }

    debug_inspect(
      provider.calls(),
      content=(
        #|[
        #|  (
        #|    "wallet_switchEthereumChain",
        #|    Array([Object({ "chainId": String("0x89") })]),
        #|  ),
        #|  (
        #|    "wallet_addEthereumChain",
        #|    Array(
        #|      [
        #|        Object(
        #|          {
        #|            "chainId": String("0x89"),
        #|            "chainName": String("Polygon Mainnet"),
        #|            "rpcUrls": Array([String("https://polygon-rpc.com")]),
        #|            "nativeCurrency": Object(
        #|              {
        #|                "name": String("POL"),
        #|                "symbol": String("POL"),
        #|                "decimals": Number(18),
        #|              },
        #|            ),
        #|            "blockExplorerUrls": Array([String("https://polygonscan.com")]),
        #|          },
        #|        ),
        #|      ],
        #|    ),
        #|  ),
        #|  (
        #|    "wallet_switchEthereumChain",
        #|    Array([Object({ "chainId": String("0x89") })]),
        #|  ),
        #|]
      ),
    )
  })
}

///|
/// A chain the wallet already knows takes the plain path: one switch, and
/// nothing is added.
async test "can switch to a known chain without adding it" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="wallet_switchEthereumChain",
      response=Json::null(),
    )
    let params = polygon_params()

    @provider.switch_or_add_chain(provider, params) catch {
      e => fail("unexpected error \{e}")
    }

    debug_inspect(
      provider.calls(),
      content=(
        #|[
        #|  (
        #|    "wallet_switchEthereumChain",
        #|    Array([Object({ "chainId": String("0x89") })]),
        #|  ),
        #|]
      ),
    )
  })
}

///|
/// Declining the add stops the dance there: the rejection reaches the caller
/// rather than being swallowed by the fallback, and no second switch is sent.
async test "error switch or add chain rejected at the add step" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new()
      .on_error(
        method_name="wallet_switchEthereumChain",
        error=@provider.ProviderError::UnrecognizedChain,
      )
      .on_error(
        method_name="wallet_addEthereumChain",
        error=@provider.ProviderError::UserRejected,
      )

    try @provider.switch_or_add_chain(provider, polygon_params()) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    inspect(provider.calls().length(), content="2")
  })
}

///|
/// A rejection at the first switch is not a 4902, so nothing is added.
async test "error switch or add chain rejected at the first switch" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="wallet_switchEthereumChain",
      error=@provider.ProviderError::UserRejected,
    )

    try @provider.switch_or_add_chain(provider, polygon_params()) catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }

    inspect(provider.calls().length(), content="1")
  })
}
