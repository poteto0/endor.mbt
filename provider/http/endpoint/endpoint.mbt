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
  /// The URL with its secrets dropped: what every message names this endpoint
  /// by. Built once, because the URL does not change and nothing above here
  /// may see the other one.
  priv display : String
  /// The caller's headers with `content-type: application/json` already in
  /// them: they do not change after construction, so neither does this.
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
///
/// Private, and `at` is its only caller, so it states no defaults of its own:
/// the defaults are `at`'s and are written once.
fn Endpoint::new(
  url : String,
  headers~ : Map[String, String],
  timeout~ : Int,
) -> Endpoint {
  let merged = { "content-type": "application/json" }
  for name, value in headers {
    merged[name] = value
  }
  Endpoint::{ url, display: display_url(url), headers: merged, timeout }
}

///|
/// A provider reading from the node at `url` — the whole of what an HTTP-only
/// caller needs, and the shape every doc example uses. `headers` and `timeout`
/// are what `Endpoint::new` takes them to be.
///
/// Raises `Config` when `url` is not an HTTP URL, or when `timeout` is not a
/// positive number of milliseconds — both are typos in the program, caught
/// before anything is sent.
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
    raise @provider.InvalidConfig("not an HTTP URL: \{display_url(url)}")
  }
  guard timeout > 0 else {
    raise @provider.InvalidConfig(
      "timeout must be a positive number of ms: \{timeout}",
    )
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
  // `with_timeout_opt` raises `Error`, so `send`'s `ProviderError` crosses it
  // as a value and is re-raised on the far side
  let outcome = @async.with_timeout_opt(self.timeout, () => {
    Ok(self.send(body)) catch {
      e => Err(e)
    }
  }) catch {
    e => raise @provider.Transport("POST \{self.display} was cancelled: \{e}")
  }
  match outcome {
    Some(Ok(text)) => text
    Some(Err(e)) => raise e
    None =>
      raise @provider.Timeout(
        "POST \{self.display} went unanswered for \{self.timeout}ms",
      )
  }
}

///|
/// One POST, without the deadline around it.
async fn Endpoint::send(
  self : Endpoint,
  body : String,
) -> String raise @provider.ProviderError {
  let (response, payload) = @client.post(self.url, body, headers=self.headers) catch {
    e => raise @provider.Transport("POST \{self.display} failed: \{e}")
  }
  guard response.code >= 200 && response.code < 300 else {
    raise @provider.HttpStatus(
      code=response.code,
      url=self.display,
      info=@provider.HttpStatusInfo::new(
        retry_after?=retry_after_seconds(response.headers),
      ),
    )
  }
  payload.text() catch {
    e =>
      raise @provider.Transport(
        "unreadable response from \{self.display}: \{e}",
      )
  }
}

///|
/// The `Retry-After` a `429` or a `503` asked for, in seconds.
///
/// Only the delta-seconds form is read. The other form the header allows is an
/// HTTP-date, which needs a clock and a date parser to compare against and is
/// not what a rate limiter sends; anything unreadable is `None`, and whoever
/// retries backs off on its own as if the header had not been there.
///
/// What the value *says* is all that is decided here. How long the SDK is
/// actually willing to sit on a request is the retry loop's, and is decided
/// there — a header this reads is one a caller can read too.
fn retry_after_seconds(headers : Map[String, String]) -> Int? {
  // header names arrive lowercased, on every backend
  guard headers.get("retry-after") is Some(value) else { return None }
  // `base=10` on purpose: the default reads `0x…` as hex, and a header that
  // spells anything but plain seconds is one to ignore rather than interpret.
  // A sign and `_` separators still get through, and neither makes the value
  // unusable — only a negative one does.
  let seconds = @string.parse_int(value.trim(), base=10) catch {
    _ => return None
  }
  guard seconds >= 0 else { return None }
  Some(seconds)
}
