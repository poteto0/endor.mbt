///|
/// An `HttpTransport` backed by `fetch` — the one a browser exposes, and the
/// one Node has had since 18. It holds the endpoint URL and posts each body to
/// it as `application/json`.
///
/// ```
/// async fn chain(
///   url : String,
/// ) -> @endor.ChainId raise @provider.ProviderError {
///   let provider = @http.HttpProvider::new(@fetch.FetchTransport::new(url))
///   @provider.chain_id(provider)
/// }
/// ```
pub struct FetchTransport {
  priv url : String
}

///|
/// A transport posting to `url`.
pub fn FetchTransport::new(url : String) -> FetchTransport {
  FetchTransport::{ url, }
}

///|
/// POST the body and answer with the response text.
///
/// `@js.post_json` answers with the status and the body, and reading that is
/// all this does: an answer that never came (status `0`) and a non-2xx one are
/// both the transport failing rather than a node answering, so both raise
/// `ProviderError::internal` — the status and the URL for one, the thrown
/// message for the other. A 2xx body is handed up untouched, JSON-RPC being
/// `HttpProvider`'s to read.
pub impl @http.HttpTransport for FetchTransport with fn post(self, body) {
  let answer = @js.post_json(self.url, body).wait() catch {
    e =>
      raise @provider.ProviderError::internal("POST \{self.url} failed: \{e}")
  }
  let (status, text) = split_status(answer)
  match status {
    0 =>
      raise @provider.ProviderError::internal(
        "POST \{self.url} failed: \{text}",
      )
    s if s >= 200 && s < 300 => text
    s => raise @provider.ProviderError::internal("HTTP \{s} from \{self.url}")
  }
}

///|
/// Split `"<status>\n<body>"` at its first newline. A body may hold newlines of
/// its own, so only the first one is a separator; an answer in no such shape
/// reads as status `0`, which is what the caller already treats as "no answer".
fn split_status(answer : String) -> (Int, String) {
  guard answer.find("\n") is Some(at) else { return (0, answer) }
  let status = @string.parse_int(answer[:at].to_owned()) catch { _ => 0 }
  (status, answer[at + 1:].to_owned())
}
