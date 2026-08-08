///|
const TRANSFER_TOPIC : String = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

///|
const TOKEN : String = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

///|
fn token() -> @types.Address {
  @types.Address::from_string(TOKEN) catch {
    e => abort("bad test address: \{e}")
  }
}

///|
fn transfer_topic() -> @types.Topic {
  @types.Topic::exactly(@types.Hex::from_string(TRANSFER_TOPIC)) catch {
    e => abort("bad test topic: \{e}")
  }
}

///|
/// One `Transfer`, as a node answers it inside `eth_getLogs`. Same shape as a
/// receipt's logs — which is why `Log::from_json` is the same decoder.
fn a_log() -> Json {
  {
    "address": TOKEN.to_json(),
    "topics": Json::array([TRANSFER_TOPIC.to_json()]),
    "data": "0x0000000000000000000000000000000000000000000000000000000000000001".to_json(),
    "blockNumber": "0x1b4".to_json(),
    "blockHash": A_BLOCK.to_json(),
    "transactionHash": TX_HASH.to_json(),
    "transactionIndex": "0x2".to_json(),
    "logIndex": "0x7".to_json(),
    "removed": false.to_json(),
  }
}

///|
async test "past logs are read back through the filter they were asked for" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getLogs",
      response=Json::array([a_log()]),
    )
    let filter = @types.LogFilter::range(
      from_block=Number(436),
      to_block=Number(437),
      address=[token()],
      topics=[Some(transfer_topic())],
    )
    let found = @provider.logs(provider, filter) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(found.length(), content="1")
    inspect(found[0].block_number, content="436")
    inspect(found[0].topics[0].to_string(), content=TRANSFER_TOPIC)
    guard provider.last_call() is Some((name, params)) else {
      fail("expected a call")
    }
    inspect(name, content="eth_getLogs")
    inspect(
      params.stringify(),
      content="[{\"fromBlock\":\"0x1b4\",\"toBlock\":\"0x1b5\",\"address\":\"\{TOKEN}\",\"topics\":[\"\{TRANSFER_TOPIC}\"]}]",
    )
  })
}

///|
/// A filter that matched nothing is an empty array, not `null`: there is no
/// absence to report, so `logs` has no option to answer with.
async test "a filter that matches nothing answers with no logs" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getLogs",
      response=Json::array([]),
    )
    let found = @provider.logs(provider, @types.LogFilter::range()) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(found.length(), content="0")
    guard provider.last_call() is Some((_, params)) else {
      fail("expected a call")
    }
    inspect(params.stringify(), content="[{}]")
  })
}

///|
/// A node that answers a shape the decoder cannot read surfaces as `Decode`,
/// naming the method that answered and keeping the `CodecError` it raised.
async test "a malformed log answer is a decode error" {
  @async.with_task_group(_ => {
    let provider = @provider.MockProvider::new().on(
      method_name="eth_getLogs",
      response=Json::string("nope"),
    )
    try @provider.logs(provider, @types.LogFilter::range()) catch {
      @provider.Decode(method_name~, ..) =>
        inspect(method_name, content="eth_getLogs")
      e => fail("expected a decode error, but not \{e}")
    } noraise {
      _ => fail("expected a string answer to be rejected")
    }
  })
}
