///|
/// The hosted providers' own URL shapes: the key is the last path segment, and
/// what is left still names the node.
test "the key a hosted url carries in its path is dropped" {
  inspect(
    display_url("https://eth-mainnet.g.alchemy.com/v2/SECRETKEY"),
    content="https://eth-mainnet.g.alchemy.com/v2/***",
  )
  inspect(
    display_url("https://mainnet.infura.io/v3/SECRETKEY"),
    content="https://mainnet.infura.io/v3/***",
  )
  // QuickNode's canonical form writes the trailing slash, which closes the
  // key's segment; the key is the whole path, with no version above it
  inspect(
    display_url("https://cold-frosty.quiknode.pro/SECRETKEY/"),
    content="https://cold-frosty.quiknode.pro/***/",
  )
  inspect(
    display_url("https://cold-frosty.quiknode.pro/SECRETKEY"),
    content="https://cold-frosty.quiknode.pro/***",
  )
}

///|
/// A key in the query is the other half of the same habit. The names stay:
/// they say which provider this is, and only the values are secret.
test "a query keeps its names and loses its values" {
  inspect(
    display_url("https://rpc.invalid/eth?key=SECRET&app=dapp"),
    content="https://rpc.invalid/***?key=***&app=***",
  )
  // a parameter spelled without a `=` is a value on its own
  inspect(
    display_url("https://rpc.invalid?SECRET"),
    content="https://rpc.invalid?***",
  )
}

///|
/// `validate_http_url` lets userinfo through on purpose, so the display form
/// is what keeps it out of a message.
test "credentials in the authority are dropped" {
  inspect(
    display_url("https://user:pass@rpc.invalid/v2"),
    content="https://rpc.invalid/***",
  )
}

///|
/// A local node has nothing to hide, and reads back as written — this is the
/// URL every recipe and every test uses.
test "a url with no secret in it is unchanged" {
  inspect(display_url("http://127.0.0.1:8545"), content="http://127.0.0.1:8545")
  inspect(display_url("https://rpc.invalid"), content="https://rpc.invalid")
  inspect(display_url("http://[::1]:8545"), content="http://[::1]:8545")
  // a path that is nothing but `/` ends no segment, so nothing is hidden
  inspect(
    display_url("http://127.0.0.1:8545/"),
    content="http://127.0.0.1:8545/",
  )
}

///|
/// A fragment is no part of which node answered, and nothing says a URL that
/// reaches here is one at all — `at` calls this on exactly the strings it is
/// about to refuse.
test "the odd shapes fold by the same rules" {
  inspect(
    display_url("https://rpc.invalid/v2/KEY#frag"),
    content="https://rpc.invalid/v2/***",
  )
  inspect(display_url("ws://127.0.0.1:8546"), content="ws://127.0.0.1:8546")
  inspect(display_url("ipc:///tmp/geth.ipc"), content="ipc:///tmp/***")
  inspect(display_url("127.0.0.1:8545"), content="127.0.0.1:8545")
  inspect(display_url(""), content="")
  inspect(display_url("http://"), content="http://")
}
