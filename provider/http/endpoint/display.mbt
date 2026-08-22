///|
/// What stands in a message where a secret was.
const REDACTED : String = "***"

///|
/// `url` with what a hosted node hides in it dropped, for a message a program
/// will print.
///
/// The URL of a hosted endpoint carries the API key: in the path
/// (`…/v2/<KEY>`), in a query value (`?key=…`), or as userinfo
/// (`https://user:pass@host/`). An error that quotes the URL as written puts
/// that key in a log, a console or a UI, so nothing above this ever sees the
/// URL as written.
///
/// What is left is what says *which* node answered — the reason an error
/// carries a URL at all: the scheme, the host and its port, and the path down
/// to its last segment.
fn display_url(url : String) -> String {
  let parts = split_url(url)
  let scheme = match parts.scheme {
    Some(scheme) => "\{scheme}://"
    None => ""
  }
  let shown = "\{scheme}\{parts.authority}\{redact_last_segment(parts.path)}"
  match parts.query {
    Some(query) => "\{shown}?\{redact_query(query)}"
    None => shown
  }
}

///|
/// The path with its last segment replaced. A trailing `/` ends no segment, so
/// there is nothing there to hide.
fn redact_last_segment(path : String) -> String {
  guard path.rev_split_once("/") is Some((head, last)) && !last.is_empty() else {
    return path
  }
  "\{head}/\{REDACTED}"
}

///|
/// The query with every value replaced, keeping the names: `?key=` is what
/// tells one hosted provider's URL from another's, and what stands after it is
/// the key itself. A parameter spelled without a `=` is a value on its own and
/// goes whole.
fn redact_query(query : String) -> String {
  query
  .split("&")
  .map(param => {
    match param.split_once("=") {
      Some((name, _)) => "\{name}=\{REDACTED}"
      None => REDACTED
    }
  })
  .join("&")
}
