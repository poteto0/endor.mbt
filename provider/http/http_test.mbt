///|
/// A transport that answers from a queue of canned response bodies and records
/// every body it was handed. What a mock wallet is to `BrowserProvider`, this
/// is to `HttpProvider`: no socket is opened, so what the tests prove is the
/// JSON-RPC framing and nothing else.
struct FakeTransport {
  responses : Array[String]
  sent : Array[String]
  /// Raised instead of answering, standing in for a refused connection.
  failure : @provider.ProviderError?
}

///|
fn FakeTransport::new(responses : Array[String]) -> FakeTransport {
  FakeTransport::{ responses, sent: [], failure: None }
}

///|
fn FakeTransport::failing(error : @provider.ProviderError) -> FakeTransport {
  FakeTransport::{ responses: [], sent: [], failure: Some(error) }
}

///|
impl @http.HttpTransport for FakeTransport with fn post(self, body) {
  self.sent.push(body)
  if self.failure is Some(e) {
    raise e
  }
  if self.responses.is_empty() {
    raise @provider.Transport("FakeTransport: no response left")
  }
  self.responses.remove(0)
}

///|
/// Drive `body` against a provider answering from `responses`, inside the task
/// group every async call needs. The transport comes back too, for the tests
/// whose assertion is about what was *sent*.
async fn on_answers(
  responses : Array[String],
  body : async (@http.HttpProvider[FakeTransport]) -> Unit,
) -> FakeTransport {
  let transport = FakeTransport::new(responses)
  @async.with_task_group(_ => body(@http.HttpProvider::new(transport)))
  transport
}

///|
/// The error a call raises, for the tests that are about a refusal. Failing
/// when the call *answers* is the half of the assertion a bare pattern match
/// would lose.
async fn refusal(
  provider : @http.HttpProvider[FakeTransport],
  method_name~ : String,
  params? : Json = Json::array([]),
) -> @provider.ProviderError raise Failure {
  try provider.request(method_name~, params~) catch {
    e => e
  } noraise {
    _ => fail("expected \{method_name} to raise, but it answered")
  }
}

///|
async test "a call is framed as JSON-RPC 2.0, and params ride along verbatim" {
  let transport = on_answers(
    [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x0\"}", "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"0x1\"}",
    ],
    provider => {
      let balance = provider.request(
        method_name="eth_getBalance",
        params=Json::array(["0xabc".to_json(), "latest".to_json()]),
      )
      debug_inspect(balance, content="String(\"0x0\")")
      let _ = provider.request(
        method_name="eth_blockNumber",
        params=Json::array([]),
      )
    },
  )
  // and the ids increment, one per call, without being asked to
  inspect(
    transport.sent[0],
    content=(
      #|{"jsonrpc":"2.0","id":1,"method":"eth_getBalance","params":["0xabc","latest"]}
    ),
  )
  inspect(
    transport.sent[1],
    content=(
      #|{"jsonrpc":"2.0","id":2,"method":"eth_blockNumber","params":[]}
    ),
  )
}

///|
async test "a JSON-RPC error object maps onto the matching ProviderError" {
  let _ = on_answers(
    [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":4001,\"message\":\"User rejected\"}}",
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32601,\"message\":\"method not found\"}}",
    ],
    provider => {
      inspect(
        refusal(provider, method_name="eth_sendTransaction"),
        content="UserRejected",
      )
      inspect(
        refusal(provider, method_name="eth_unheardOf"),
        content=(
          #|Rpc(code=-32601, message="method not found")
        ),
      )
    },
  )
}

///|
/// Whatever cannot be read is still an error: an `error` member of the wrong
/// shape, a body that is not JSON-RPC at all, and a response carrying neither
/// member all report as `MalformedResponse` rather than as an answer.
async test "an unreadable answer is a malformed response, never a result" {
  for
    body in [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":\"boom\"}", "<html>502 Bad Gateway</html>",
      "{\"jsonrpc\":\"2.0\",\"id\":1}",
    ] {
    let _ = on_answers([body], provider => {
      assert_true(
        refusal(provider, method_name="eth_chainId")
        is @provider.MalformedResponse(_),
      )
    })
  }
}

///|
async test "a null result is an answer, not a failure" {
  let _ = on_answers(["{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}"], provider => {
    let result = provider.request(
      method_name="eth_getTransactionReceipt",
      params=Json::array(["0xdead".to_json()]),
    )
    assert_eq(result, Json::null())
  })
}

///|
async test "a response answering some other request is refused" {
  let _ = on_answers(["{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":\"0x1\"}"], provider => {
    inspect(
      refusal(provider, method_name="eth_chainId"),
      content=(
        #|MalformedResponse("id mismatch: sent 1, got 7")
      ),
    )
  })
}

///|
/// A node that omits the id is answering the only request in flight, so there
/// is nothing to mismatch — unlike one that names a different request.
async test "a response with no id at all is accepted" {
  let _ = on_answers(["{\"jsonrpc\":\"2.0\",\"result\":\"0x1\"}"], provider => {
    debug_inspect(
      provider.request(method_name="eth_chainId", params=Json::array([])),
      content="String(\"0x1\")",
    )
  })
}

///|
async test "a transport that cannot reach the node propagates its error" {
  let transport = FakeTransport::failing(
    @provider.Transport("POST http://127.0.0.1:1 failed"),
  )
  let provider = @http.HttpProvider::new(transport)
  @async.with_task_group(_ => {
    inspect(
      refusal(provider, method_name="eth_chainId"),
      content=(
        #|Transport("POST http://127.0.0.1:1 failed")
      ),
    )
  })
}

///|
/// The methods HTTP cannot serve are refused *before* the transport is
/// touched — the assertion is that nothing was sent, not merely that it failed.
async test "wallet methods are refused without a round trip" {
  let transport = on_answers([], provider => {
    for name in ["wallet_switchEthereumChain", "eth_requestAccounts"] {
      inspect(refusal(provider, method_name=name), content="UnsupportedMethod")
    }
  })
  inspect(transport.sent.length(), content="0")
}

///|
/// The point of the whole package: the typed helpers, unchanged, driven over
/// HTTP. `chain_id` and `block_number` decode into domain values, so what this
/// asserts is that the framing above really carries the read layer.
async test "the typed helpers decode over an HttpProvider" {
  let _ = on_answers(
    [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x7a69\"}", "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"0x10\"}",
    ],
    provider => {
      inspect(@provider.chain_id(provider), content="ChainId(31337)")
      inspect(@provider.block_number(provider), content="16")
    },
  )
}
