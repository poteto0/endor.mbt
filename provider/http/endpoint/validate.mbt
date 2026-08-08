///|
/// Whether `url` is an HTTP endpoint this transport can POST to: an `http://`
/// or `https://` scheme, and a host standing after it.
///
/// The host is what makes this worth checking. A URL missing one — `http://`,
/// `http://:8545`, `http://user@/path` — is a typo that would otherwise
/// surface as a connection error at the first request, one call away from the
/// mistake. Anything past the host is the node's business: a path, a query, a
/// fragment and credentials all pass.
///
/// The scheme is matched as written, so `HTTP://` fails. Normalising case is
/// the caller's, above this.
fn validate_http_url(url : String) -> Bool {
  let rest = if url.has_prefix("http://") {
    url[7:]
  } else if url.has_prefix("https://") {
    url[8:]
  } else {
    return false
  }

  // The authority runs to the first delimiter; a `@` means everything read so
  // far was credentials, and the host starts over after it.
  let host = []
  for c in rest {
    if c is ('/' | '?' | '#') {
      break
    } else if c == '@' {
      host.clear()
    } else {
      host.push(c)
    }
  }
  guard host is [first, ..] else { return false }

  // Drop the port. In an IPv6 literal the colons are inside the brackets and
  // the port follows `]`, so the brackets have to be read first.
  let hostname = if first == '[' {
    guard host.search(']') is Some(close) else { return false }
    host[1:close]
  } else {
    match host.search(':') {
      Some(colon) => host[:colon]
      None => host[:]
    }
  }
  !hostname.is_empty() && !hostname.iter().any(Char::is_whitespace)
}
