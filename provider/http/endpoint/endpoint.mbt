///|
/// A node's JSON-RPC endpoint: the URL to POST to, and any headers that go with
/// every request — the API key a hosted provider wants, most often.
///
/// The `HttpTransport` almost every caller wants, and the reason
/// `at` exists to skip naming it. It is written against
/// `moonbitlang/async`'s HTTP client, which is implemented per backend —
/// `fetch` on `js`, sockets and TLS on `native` and `wasm` — so this SDK needs
/// no FFI of its own and the same code reads a chain from a browser, a CLI or
/// a server.
///
/// ```
/// async fn chain(
///   url : String,
/// ) -> @endor.ChainId raise @provider.ProviderError {
///   @provider.chain_id(@endpoint.at(url))
/// }
/// ```
pub struct Endpoint {
  priv url : String
  priv headers : Map[String, String]
  priv timeout : Int
}

///|
/// How long one POST may take, in milliseconds, when the caller names no
/// deadline of its own. Generous: it is there so a node that stops answering
/// mid-request fails instead of hanging forever, not to bound a slow one.
pub const DEFAULT_TIMEOUT_MS : Int = 30_000

///|
/// An endpoint at `url`. `headers` are sent with every request, on top of the
/// `content-type` JSON-RPC needs — an `Authorization` bearer, an `x-api-key`.
/// `timeout` bounds the whole POST — connecting, sending and reading the body.
fn Endpoint::new(
  url : String,
  headers? : Map[String, String] = Map([]),
  timeout? : Int = DEFAULT_TIMEOUT_MS,
) -> Endpoint {
  Endpoint::{ url, headers, timeout }
}

///|
/// A provider reading from the node at `url` — the whole of what an HTTP-only
/// caller needs, and the shape every doc example uses. `headers` and `timeout`
/// are what `Endpoint::new` takes them to be.
///
/// Raises `Config` when `url` is not an HTTP URL — that is a typo in the
/// program, caught before anything is sent.
///
/// ```
/// let provider = @endpoint.at("http://127.0.0.1:8545")
/// ignore(provider)
/// ```
pub fn at(
  url : String,
  headers? : Map[String, String] = Map([]),
  timeout? : Int = DEFAULT_TIMEOUT_MS,
) -> @http.HttpProvider[Endpoint] raise @provider.ProviderError {
  guard validate_http_url(url) else {
    raise @provider.Config("not an HTTP URL: \{url}")
  }
  @http.HttpProvider::new(Endpoint::new(url, headers~, timeout~))
}

///|
/// POST the body and answer with the response text.
///
/// The three ways this fails are three different things to do about it, so
/// they are three variants: nothing got through (`Transport`), something
/// answered with a status that is not 2xx (`HttpStatus`, which carries the
/// status so `429` and `503` can be retried and `401` cannot), and nothing
/// answered inside `timeout` (`Timeout`). A 2xx body is handed up untouched:
/// reading JSON-RPC out of it is `HttpProvider`'s.
///
/// The deadline covers the whole exchange rather than each half of it,
/// because a node that dribbles a response out forever is no better than one
/// that never connects.
pub impl @http.HttpTransport for Endpoint with fn post(self, body) {
  // `with_timeout_opt` raises `Error` — a cancellation, from the task group it
  // runs the POST in. `send` answers with a `Result` so that nothing else can
  // arrive here, which is what lets this one branch stay honest.
  let outcome = @async.with_timeout_opt(self.timeout, () => self.send(body)) catch {
    e => raise @provider.Transport("POST \{self.url} was cancelled: \{e}")
  }
  match outcome {
    Some(Ok(text)) => text
    Some(Err(e)) => raise e
    None =>
      raise @provider.Timeout(
        "POST \{self.url} went unanswered for \{self.timeout}ms",
      )
  }
}

///|
/// One POST, without the deadline around it.
///
/// It answers with a `Result` rather than raising, so that the only thing that
/// can come out of `with_timeout_opt` is the deadline: that combinator's own
/// error type is `Error`, and letting a `ProviderError` travel through it would
/// widen `post`'s.
async fn Endpoint::send(
  self : Endpoint,
  body : String,
) -> Result[String, @provider.ProviderError] {
  let headers = apply_headers(self.headers)
  let (response, payload) = @client.post(self.url, body, headers~) catch {
    e => return Err(@provider.Transport("POST \{self.url} failed: \{e}"))
  }
  guard response.code >= 200 && response.code < 300 else {
    return Err(@provider.HttpStatus(code=response.code, url=self.url))
  }
  Ok(
    payload.text() catch {
      e =>
        return Err(
          @provider.Transport("unreadable response from \{self.url}: \{e}"),
        )
    },
  )
}

///|
/// add `content-type: application/json` to `headers`, and return the result.
fn apply_headers(headers : Map[String, String]) -> Map[String, String] {
  let applied_headers = { "content-type": "application/json" }
  for name, value in headers {
    applied_headers[name] = value
  }
  applied_headers
}
