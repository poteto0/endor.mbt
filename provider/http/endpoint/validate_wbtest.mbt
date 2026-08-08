///|
test "accepts http and https urls" {
  inspect(validate_http_url("http://127.0.0.1:8545"), content="true")
  inspect(validate_http_url("https://example.invalid"), content="true")
  inspect(validate_http_url("https://example.invalid/v2"), content="true")
  // a path, a query, a fragment and credentials are the node's business
  inspect(
    validate_http_url("https://user:pass@example.invalid/v2?key=abc#frag"),
    content="true",
  )
  // an IPv6 literal, with and without a port
  inspect(validate_http_url("http://[::1]:8545"), content="true")
  inspect(validate_http_url("http://[2001:db8::1]/v2"), content="true")
}

///|
test "rejects other schemes" {
  inspect(validate_http_url("ws://127.0.0.1:8546"), content="false")
  inspect(validate_http_url("wss://example.invalid"), content="false")
  inspect(validate_http_url("ipc:///tmp/geth.ipc"), content="false")
  inspect(validate_http_url("file:///etc/passwd"), content="false")
  // no scheme at all
  inspect(validate_http_url("example.invalid/v2"), content="false")
  inspect(validate_http_url("127.0.0.1:8545"), content="false")
  // a scheme that only starts the same way
  inspect(validate_http_url("https:/example.invalid"), content="false")
  inspect(validate_http_url("httpx://example.invalid"), content="false")
}

///|
test "rejects the empty and blank url" {
  inspect(validate_http_url(""), content="false")
  inspect(validate_http_url(" "), content="false")
  // leading whitespace is not trimmed, so the prefix no longer matches
  inspect(validate_http_url(" http://127.0.0.1:8545"), content="false")
}

///|
test "the scheme is matched as written" {
  // normalising case is the caller's, above this
  inspect(validate_http_url("HTTP://127.0.0.1:8545"), content="false")
  inspect(validate_http_url("Https://example.invalid"), content="false")
}

///|
test "rejects a url with no host" {
  inspect(validate_http_url("http://"), content="false")
  inspect(validate_http_url("https://"), content="false")
  // a path, a query or a fragment where the host should be
  inspect(validate_http_url("http:///v2"), content="false")
  inspect(validate_http_url("http://?key=abc"), content="false")
  inspect(validate_http_url("http://#frag"), content="false")
  // a port with nothing to connect to
  inspect(validate_http_url("http://:8545"), content="false")
  inspect(validate_http_url("http://:8545/v2"), content="false")
  // credentials, and then no host
  inspect(validate_http_url("http://user@"), content="false")
  inspect(validate_http_url("http://user:pass@/v2"), content="false")
  inspect(validate_http_url("http://user@:8545"), content="false")
  // an unclosed IPv6 literal, and an empty one
  inspect(validate_http_url("http://[::1"), content="false")
  inspect(validate_http_url("http://[]:8545"), content="false")
}

///|
test "rejects whitespace in the host" {
  inspect(validate_http_url("http://exam ple.invalid"), content="false")
  inspect(validate_http_url("http://example.invalid /v2"), content="false")
  // past the host it is not this function's to judge
  inspect(validate_http_url("http://example.invalid/a b"), content="true")
}

///|
test "the host is all that is checked" {
  // the `@` is credentials, however little sense they make
  inspect(validate_http_url("http://@example.invalid"), content="true")
  // nothing here knows what a TLD is
  inspect(validate_http_url("http://nonsense"), content="true")
  inspect(validate_http_url("http://....."), content="true")
}
