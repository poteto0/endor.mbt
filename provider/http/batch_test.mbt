///|
/// The two reads every test below folds: unrelated, concurrent, and answered
/// under ids 1 and 2.
fn two_reads() -> Array[@provider.BatchCall] {
  [
    @provider.BatchCall::new(method_name="eth_chainId", params=Json::array([])),
    @provider.BatchCall::new(
      method_name="eth_blockNumber",
      params=Json::array([]),
    ),
  ]
}

///|
/// What a node answers `two_reads()` with, in order.
fn two_answers() -> String {
  let body =
    #|[{"jsonrpc":"2.0","id":1,"result":"0x1"},{"jsonrpc":"2.0","id":2,"result":"0x2a"}]
  body
}

///|
/// Two reads, concurrently, with nothing to say to each other. The window is
/// the only thing that knows they are related, and one POST is the whole point
/// of this feature.
async test "concurrent calls in one window leave as a single POST" {
  let answered = two_answers()
  let transport = on_answers(
    [answered],
    batch=@provider.BatchPolicy::default(),
    provider => {
      let answers = @provider.request_many(provider, two_reads())
      debug_inspect(
        answers,
        content="[Ok(String(\"0x1\")), Ok(String(\"0x2a\"))]",
      )
    },
  )
  assert_eq(transport.sent.length(), 1)
  inspect(
    transport.sent[0],
    content=(
      #|[{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]},{"jsonrpc":"2.0","id":2,"method":"eth_blockNumber","params":[]}]
    ),
  )
}

///|
/// JSON-RPC lets a node answer a batch in any order, so position says nothing
/// and the id says everything. Getting this wrong hands one call another call's
/// answer without anything looking wrong.
async test "answers are matched by id, not by position" {
  let backwards =
    #|[{"jsonrpc":"2.0","id":2,"result":"0x2a"},{"jsonrpc":"2.0","id":1,"result":"0x1"}]
  let _ = on_answers([backwards], batch=@provider.BatchPolicy::default(), provider => {
    let answers = @provider.request_many(provider, two_reads())
    debug_inspect(
      answers,
      content="[Ok(String(\"0x1\")), Ok(String(\"0x2a\"))]",
    )
  })
}

///|
/// One element failing is one call failing. The batch is a transport detail,
/// and it must not become a shared fate.
async test "an error on one element leaves the others answered" {
  let mixed =
    #|[{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"nope"}},{"jsonrpc":"2.0","id":2,"result":"0x2a"}]
  let _ = on_answers([mixed], batch=@provider.BatchPolicy::default(), provider => {
    let answers = @provider.request_many(provider, two_reads())
    assert_true(answers[0] is Err(Rpc(code=-32601, ..)))
    debug_inspect(answers[1], content="Ok(String(\"0x2a\"))")
  })
}

///|
/// A node that refuses the batch as a whole answers a single error object where
/// the array should be. That is nobody's individual failure, so it reaches
/// everyone in the window rather than being pinned on one element.
async test "a whole-batch error object reaches every call in the window" {
  let refused =
    #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"batch too large"}}
  let _ = on_answers([refused], batch=@provider.BatchPolicy::default(), provider => {
    let answers = @provider.request_many(provider, two_reads())
    assert_true(answers[0] is Err(Rpc(code=-32600, ..)))
    assert_true(answers[1] is Err(Rpc(code=-32600, ..)))
  })
}

///|
/// An id that was never sent, or one answered twice, means the mapping is not
/// trustworthy — and an untrustworthy mapping is the failure mode this whole
/// feature has to not have, so the batch fails whole. An id that never came
/// back is only that call's problem, so it is only that call that fails.
async test "an id that is unknown or doubled fails the batch" {
  let unknown =
    #|[{"jsonrpc":"2.0","id":7,"result":"0x1"},{"jsonrpc":"2.0","id":2,"result":"0x2a"}]
  let doubled =
    #|[{"jsonrpc":"2.0","id":1,"result":"0x1"},{"jsonrpc":"2.0","id":1,"result":"0x2a"}]
  for body in [unknown, doubled] {
    let _ = on_answers([body], batch=@provider.BatchPolicy::default(), provider => {
      let answers = @provider.request_many(provider, two_reads())
      assert_true(answers[0] is Err(MalformedResponse(_)))
      assert_true(answers[1] is Err(MalformedResponse(_)))
    })
  }
}

///|
async test "an id that never came back fails only its own call" {
  let short =
    #|[{"jsonrpc":"2.0","id":1,"result":"0x1"}]
  let _ = on_answers([short], batch=@provider.BatchPolicy::default(), provider => {
    let answers = @provider.request_many(provider, two_reads())
    debug_inspect(answers[0], content="Ok(String(\"0x1\"))")
    assert_true(answers[1] is Err(MalformedResponse(_)))
  })
}

///|
/// The window closes on `max_size` without waiting out `wait`. The assertion is
/// that this test finishes: a `wait` of a minute is one nobody sits through.
async test "reaching max_size closes the window without waiting" {
  let answered = two_answers()
  let transport = on_answers(
    [answered],
    batch=@provider.BatchPolicy::new(wait=60_000, max_size=2),
    provider => {
      let answers = @provider.request_many(provider, two_reads())
      debug_inspect(
        answers,
        content="[Ok(String(\"0x1\")), Ok(String(\"0x2a\"))]",
      )
    },
  )
  assert_eq(transport.sent.length(), 1)
}

///|
/// The overflow of a full window waits for the next one rather than being split
/// into a second POST alongside it: a node with a cap on batch length is not
/// helped by being sent two batches at once.
async test "what does not fit in a window goes in the next one" {
  let first =
    #|[{"jsonrpc":"2.0","id":1,"result":"0x1"},{"jsonrpc":"2.0","id":2,"result":"0x2"}]
  let second =
    #|[{"jsonrpc":"2.0","id":3,"result":"0x3"}]
  let transport = on_answers(
    [first, second],
    batch=@provider.BatchPolicy::new(wait=1, max_size=2),
    provider => {
      let answers = @provider.request_many(
        provider,
        [1, 2, 3].map(_ => {
          @provider.BatchCall::new(
            method_name="eth_blockNumber",
            params=Json::array([]),
          )
        }),
      )
      debug_inspect(
        answers,
        content="[Ok(String(\"0x1\")), Ok(String(\"0x2\")), Ok(String(\"0x3\"))]",
      )
    },
  )
  assert_eq(transport.sent.length(), 2)
}

///|
/// The default is off, and off means byte-for-byte what it was before: one
/// call, one POST, no array anywhere.
async test "a provider that was never given a window still sends one POST each" {
  let chain =
    #|{"jsonrpc":"2.0","id":1,"result":"0x1"}
  let block =
    #|{"jsonrpc":"2.0","id":2,"result":"0x2a"}
  let transport = on_answers([chain, block], provider => {
    let answers = @provider.request_many(provider, two_reads())
    debug_inspect(
      answers,
      content="[Ok(String(\"0x1\")), Ok(String(\"0x2a\"))]",
    )
  })
  assert_eq(transport.sent.length(), 2)
}

///|
/// A batch is retried whole, so a call that must be sent at most once cannot be
/// in one. It takes the unbatched path and its own POST, next to a window that
/// is folding everything else.
async test "a send-once method never enters the window" {
  let hash =
    #|{"jsonrpc":"2.0","id":1,"result":"0xhash"}
  let chain =
    #|[{"jsonrpc":"2.0","id":2,"result":"0x1"}]
  let transport = on_answers(
    [hash, chain],
    batch=@provider.BatchPolicy::default(),
    provider => {
      let sent = provider.request(
        method_name="eth_sendTransaction",
        params=Json::array([]),
      )
      debug_inspect(sent, content="String(\"0xhash\")")
      let answer = provider.request(
        method_name="eth_chainId",
        params=Json::array([]),
      )
      debug_inspect(answer, content="String(\"0x1\")")
    },
  )
  inspect(
    transport.sent[0],
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"eth_sendTransaction","params":[]}
    ),
  )
  inspect(
    transport.sent[1],
    content=(
      #|[{"jsonrpc":"2.0","id":2,"method":"eth_chainId","params":[]}]
    ),
  )
}

///|
/// The call that happens to be first is the one that sends, so its giving up is
/// the case that could strand everyone else. It does not: the role goes back,
/// the next one awake takes it, and the abandoned call is not in the batch it
/// sends.
async test "a cancelled sender hands the window to the next call" {
  let answered =
    #|[{"jsonrpc":"2.0","id":2,"result":"0x2a"}]
  let transport = FakeTransport::new([answered])
  let provider = @http.HttpProvider::new(transport).with_batch(
    @provider.BatchPolicy::new(wait=200),
  )
  @async.with_task_group(group => {
    // first into the window, so the sender — and then it is taken away
    let doomed = group.spawn(allow_failure=true, () => {
      provider.request(method_name="eth_chainId", params=Json::array([]))
    })
    // second, so it only ever waits — until the role comes to it
    let survivor = group.spawn(() => {
      provider.request(method_name="eth_blockNumber", params=Json::array([]))
    })
    doomed.cancel()
    debug_inspect(survivor.wait(), content="String(\"0x2a\")")
  })
  assert_eq(transport.sent.length(), 1)
  inspect(
    transport.sent[0],
    content=(
      #|[{"jsonrpc":"2.0","id":2,"method":"eth_blockNumber","params":[]}]
    ),
  )
}

///|
/// One `429` for a window is one resend of the window, not N resends of N calls
/// that were never sent separately in the first place.
async test "a retryable failure retries the POST once, not once per call" {
  let busy =
    #|{"jsonrpc":"2.0","id":null,"error":{"code":-32005,"message":"slow down"}}
  let answered = two_answers()
  let transport = on_answers(
    [busy, answered],
    batch=@provider.BatchPolicy::default(),
    retry=@provider.RetryPolicy::new(strategy=Immediate, max_retry=1),
    provider => {
      let answers = @provider.request_many(provider, two_reads())
      debug_inspect(
        answers,
        content="[Ok(String(\"0x1\")), Ok(String(\"0x2a\"))]",
      )
    },
  )
  assert_eq(transport.sent.length(), 2)
}

///|
/// `BatchPolicy` clamps rather than trusting: a window of no calls is a
/// spelling of a window of one, and a negative wait is no wait.
test "a policy outside its range clamps into it" {
  let policy = @provider.BatchPolicy::new(wait=-5, max_size=0)
  assert_eq(policy.wait(), 0)
  assert_eq(policy.max_size(), 1)
}
