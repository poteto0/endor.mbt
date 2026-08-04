///|
/// A token nobody deployed, and the account that holds none of it.
fn token() -> @types.Address {
  address("0x1f9840a85d5af5bf1d1762f925bdaddc4201f984")
}

///|
fn holder() -> @types.Address {
  address("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
}

///|
fn address(s : String) -> @types.Address {
  @types.Address::from_string(s) catch {
    e => abort("bad test address: \{e}")
  }
}

///|
/// A provider that answers one `eth_call` with `data`, and records what it was
/// asked — the calldata is half of what these tests are about.
fn answering(data : String) -> @provider.MockProvider {
  @provider.MockProvider::new().on(
    method_name="eth_call",
    response=Json::string(data),
  )
}

///|
/// The calldata the last call carried, so a test can pin the selector and the
/// arguments the SDK put on the wire.
fn calldata(p : @provider.MockProvider) -> String {
  guard p.last_call() is Some((_, params)) else { return "no call" }
  guard params is [Object(request), ..] else { return "no request object" }
  guard request.get("data") is Some(String(data)) else { return "no data" }
  data
}

///|
async test "balance_of asks balanceOf and reads the number back" {
  @async.with_task_group(_ => {
    let wallet = answering(
      "0x00000000000000000000000000000000000000000000000000000000000003e8",
    )
    let balance = @erc20.Erc20::new(token()).balance_of(wallet, holder()) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(balance, content="1000")
    inspect(
      calldata(wallet),
      content="0x70a08231" +
        "000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    )
  })
}

///|
/// `decimals` is a `uint8`, so it comes back as a plain `Int` — the one place
/// a token's numbers are small enough to be one.
async test "decimals and total_supply read the token's scale" {
  @async.with_task_group(_ => {
    let wallet = answering(
      "0x0000000000000000000000000000000000000000000000000000000000000006",
    )
    let usdc = @erc20.Erc20::new(token())
    inspect(
      usdc.decimals(wallet) catch {
        e => fail("unexpected error: \{e}")
      },
      content="6",
    )
    inspect(calldata(wallet), content="0x313ce567")
    let wallet = answering(
      "0x00000000000000000000000000000000000000000000d3c21bcecceda1000000",
    )
    inspect(
      usdc.total_supply(wallet) catch {
        e => fail("unexpected error: \{e}")
      },
      content="1000000000000000000000000",
    )
    inspect(calldata(wallet), content="0x18160ddd")
  })
}

///|
/// `name` and `symbol` answer strings, which are dynamic: an offset, a length
/// and the UTF-8 bytes.
async test "name and symbol read the token's strings" {
  @async.with_task_group(_ => {
    let wallet = answering(
      "0x0000000000000000000000000000000000000000000000000000000000000020" +
      "0000000000000000000000000000000000000000000000000000000000000004" +
      "5553444300000000000000000000000000000000000000000000000000000000",
    )
    inspect(
      @erc20.Erc20::new(token()).symbol(wallet) catch {
        e => fail("unexpected error: \{e}")
      },
      content="USDC",
    )
    inspect(calldata(wallet), content="0x95d89b41")
  })
}

///|
/// A transfer signs, so it goes out as `eth_sendTransaction` — to the token,
/// with the amount in the calldata and no ether attached.
async test "transfer sends calldata to the token" {
  @async.with_task_group(_ => {
    let wallet = @provider.MockProvider::new().on(
      method_name="eth_sendTransaction",
      response=Json::string(
        "0x00000000000000000000000000000000000000000000000000000000000000ff",
      ),
    )
    let hash = @erc20.Erc20::new(token()).transfer(
      wallet,
      from=holder(),
      to=address("0x000000000000000000000000000000000000dead"),
      amount=1000000N,
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      hash,
      content="0x00000000000000000000000000000000000000000000000000000000000000ff",
    )
    inspect(
      calldata(wallet),
      content="0xa9059cbb" +
        "000000000000000000000000000000000000000000000000000000000000dead" +
        "00000000000000000000000000000000000000000000000000000000000f4240",
    )
  })
}

///|
/// The failure a dapp actually hits: an address that is not the token it was
/// taken for. A contract that is not there answers `0x`, which no getter's
/// return type can be read out of.
async test "an address that is not the token is an Abi error" {
  @async.with_task_group(_ => {
    let wallet = answering("0x")
    try
      @erc20.Erc20::new(token()).balance_of(wallet, holder()) |> ignore
    catch {
      e =>
        inspect(
          e,
          content="Abi(InvalidData(expected a word at byte 0, but the data is 0 bytes))",
        )
    } noraise {
      _ => fail("expected an error")
    }
  })
}

///|
/// A wallet-side failure keeps its `ProviderError` intact inside `Rpc`, so the
/// 4001 a dapp already handles is still recognisable here.
async test "a rejected prompt stays a ProviderError" {
  @async.with_task_group(_ => {
    let wallet = @provider.MockProvider::new().on_error(
      method_name="eth_sendTransaction",
      error=UserRejected,
    )
    try
      @erc20.Erc20::new(token()).approve(
        wallet,
        from=holder(),
        spender=address("0x000000000000000000000000000000000000dead"),
        amount=1N,
      )
      |> ignore
    catch {
      Rpc(UserRejected) => inspect("rejected", content="rejected")
      e => fail("unexpected error: \{e}")
    } noraise {
      _ => fail("expected an error")
    }
  })
}

///|
/// A log of `token`, with the topics and data given.
fn transfer_log(topics : Array[@types.Hex], data : String) -> @types.Log {
  let hex = s => {
    @types.Hex::from_string(s) catch {
      e => abort("bad test hex: \{e}")
    }
  }
  {
    address: token(),
    topics,
    data: hex(data),
    block_number: 1,
    block_hash: @types.BlockHash::from_string("0x" + "11".repeat(32)) catch {
      e => abort("bad test hash: \{e}")
    },
    transaction_hash: @types.TxHash::from_string("0x" + "22".repeat(32)) catch {
      e => abort("bad test hash: \{e}")
    },
    transaction_index: 0,
    log_index: 0,
    removed: false,
  }
}

///|
/// A padded word, from the digits that are not padding.
fn word(digits : String) -> @types.Hex {
  @types.Hex::from_string("0x" + "0".repeat(64 - digits.length()) + digits) catch {
    e => abort("bad test word: \{e}")
  }
}

///|
/// `from` and `to` were topics and `value` was data; what comes back is the
/// three of them in the order the event declares them.
test "decode_transfer reads a transfer out of its log" {
  let (from, to, value) = @erc20.Erc20::decode_transfer(
    transfer_log(
      [
        @erc20.Erc20::transfer_topic(),
        word("f39fd6e51aad88f6f4ce6ab8827279cfffb92266"),
        word("000000000000000000000000000000000000dead"),
      ],
      "0x" + "0".repeat(62) + "2a",
    ),
  )
  assert_eq(from, holder())
  assert_eq(to, address("0x000000000000000000000000000000000000dead"))
  assert_eq(value, 42N)
}

///|
/// A receipt holds the logs of every contract a transaction touched, so a log
/// that is not a transfer has to be refused rather than decoded.
test "decode_transfer refuses a log of another event" {
  try
    @erc20.Erc20::decode_transfer(
      transfer_log(
        [@abi.event_topic("Approval(address,address,uint256)")],
        "0x",
      ),
    )
    |> ignore
  catch {
    Abi(_) => ()
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("expected a log of another event to be refused")
  }
}

///|
/// The topic a receipt's logs are matched against to find the transfers.
test "transfer_topic is the Transfer event's topic" {
  inspect(
    @erc20.Erc20::transfer_topic(),
    content="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
  )
}
