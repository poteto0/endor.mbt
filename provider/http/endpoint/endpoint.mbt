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
}

///|
/// An endpoint at `url`. `headers` are sent with every request, on top of the
/// `content-type` JSON-RPC needs — an `Authorization` bearer, an `x-api-key`.
fn Endpoint::new(
  url : String,
  headers? : Map[String, String] = Map([]),
) -> Endpoint {
  Endpoint::{ url, headers }
}

///|
/// A provider reading from the node at `url` — the whole of what an HTTP-only
/// caller needs, and the shape every doc example uses. `headers` are what
/// `Endpoint::new` takes them to be.
/// 
/// raises `ProviderError::internal` if `url` is not a valid HTTP URL, or if the
///
/// ```
/// let provider = @endpoint.at("http://127.0.0.1:8545")
/// ignore(provider)
/// ```
pub fn at(
  url : String,
  headers? : Map[String, String] = Map([]),
) -> @http.HttpProvider[Endpoint] raise @provider.ProviderError {
  guard validate_http_url(url) else {
    raise @provider.ProviderError::internal("invalid HTTP URL: \{url}")
  }
  @http.HttpProvider::new(Endpoint::new(url, headers~))
}

///|
/// POST the body and answer with the response text.
///
/// A request that never got an answer and a non-2xx status are both the
/// transport failing rather than a node answering, so both raise
/// `ProviderError::internal`. A 2xx body is handed up untouched: reading
/// JSON-RPC out of it is `HttpProvider`'s.
pub impl @http.HttpTransport for Endpoint with fn post(self, body) {
  let headers = apply_headers(self.headers)
  let (response, payload) = @client.post(self.url, body, headers~) catch {
    e =>
      raise @provider.ProviderError::internal("POST \{self.url} failed: \{e}")
  }
  guard response.code >= 200 && response.code < 300 else {
    raise @provider.ProviderError::internal(
      "HTTP \{response.code} from \{self.url}",
    )
  }
  payload.text() catch {
    e =>
      raise @provider.ProviderError::internal(
        "unreadable response from \{self.url}: \{e}",
      )
  }
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
