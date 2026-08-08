///|
/// The URLs a node is actually reached at, in the shapes callers write them.
/// Nothing here opens a socket: what `at` promises before a request is made is
/// that the URL it was handed can be POSTed to at all.
test "at accepts the urls a node is reached at" {
  ignore(@endpoint.at("http://127.0.0.1:8545"))
  ignore(@endpoint.at("https://example.invalid/v2"))
  ignore(@endpoint.at("https://example.invalid/v2?key=abc"))
  ignore(@endpoint.at("http://[::1]:8545"))
  // headers are the hosted-provider case, and change nothing about the URL
  ignore(
    @endpoint.at("https://example.invalid/v2", headers={
      "Authorization": "Bearer …",
    }),
  )
}

///|
/// A URL with no host would otherwise surface as a connection error at the
/// first request, a call away from the typo that caused it.
test "at refuses a url with no host" {
  for url in ["http://", "http://:8545", "http://user@/v2"] {
    try ignore(@endpoint.at(url)) catch {
      @provider.InvalidConfig(message) =>
        assert_eq(message, "not an HTTP URL: \{url}")
      e => fail("expected a configuration error for \{url}, but not \{e}")
    } noraise {
      _ => fail("expected \{url} to be refused")
    }
  }
}

///|
/// The other transports have their own providers; a URL naming one is a
/// mistake this catches rather than a request that fails later.
test "at refuses a scheme it cannot POST to" {
  for url in ["ws://127.0.0.1:8546", "ipc:///tmp/geth.ipc", "127.0.0.1:8545"] {
    try ignore(@endpoint.at(url)) catch {
      @provider.InvalidConfig(message) =>
        assert_eq(message, "not an HTTP URL: \{url}")
      e => fail("expected a configuration error for \{url}, but not \{e}")
    } noraise {
      _ => fail("expected \{url} to be refused")
    }
  }
}
