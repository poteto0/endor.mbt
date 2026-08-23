///|
/// Whether `url` is an HTTP endpoint this transport can POST to: an `http://`
/// or `https://` scheme, and a host standing after it.
///
/// The host is what makes this worth checking — a URL missing one is a typo that
/// would otherwise surface as a connection error one call away. Anything past
/// the host passes. The scheme is matched as written, so `HTTP://` fails.
fn validate_http_url(url : String) -> Bool {
  let parts = split_url(url)
  guard parts.scheme is Some("http" | "https") else { return false }
  guard hostname_of(parts.authority) is Some(hostname) else { return false }
  !hostname.is_empty() && !hostname.iter().any(Char::is_whitespace)
}

///|
/// The authority without its port. In an IPv6 literal the colons are inside
/// the brackets and the port follows `]`, so the brackets are read first; an
/// unclosed one is no hostname at all.
fn hostname_of(authority : String) -> StringView? {
  guard authority is [first, ..] else { return Some(authority[:]) }
  if first == '[' {
    guard authority.find("]") is Some(close) else { return None }
    return Some(authority[1:close])
  }
  match authority.find(":") {
    Some(colon) => Some(authority[:colon])
    None => Some(authority[:])
  }
}
