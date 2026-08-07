///|
/// Exhaustive check of EIP-1193 / EIP-1474 code -> variant mapping.
test "from_code maps standard EIP-1193 codes" {
  inspect(ProviderError::from_code(4001, ""), content="UserRejected")
  inspect(ProviderError::from_code(4100, ""), content="Unauthorized")
  inspect(ProviderError::from_code(4200, ""), content="UnsupportedMethod")
  inspect(ProviderError::from_code(4900, ""), content="Disconnected")
  inspect(ProviderError::from_code(4901, ""), content="ChainDisconnected")
  inspect(ProviderError::from_code(4902, ""), content="UnrecognizedChain")
}

///|
/// Unknown codes fall through to the generic `Rpc` variant, preserving code
/// and message.
test "from_code falls through to Rpc" {
  inspect(
    ProviderError::from_code(-32603, "internal"),
    content=(
      #|Rpc(code=-32603, message="internal")
    ),
  )
  inspect(
    ProviderError::from_code(-32000, "revert"),
    content=(
      #|Rpc(code=-32000, message="revert")
    ),
  )
  inspect(
    ProviderError::from_code(0, "?"),
    content=(
      #|Rpc(code=0, message="?")
    ),
  )
}

///|
/// The revert `Error(string)` of a `require` that failed, as the three shapes
/// nodes and wallets put it in `error.data`.
test "from_code finds the revert wherever the node put it" {
  let revert = "0x08c379a0"
  let shapes : Array[Json] = [
    // geth, Anvil: the hex, right there
    revert.to_json(),
    // a wallet that wrapped the node's answer
    { "data": revert.to_json() },
    // …and one that kept the node's own error alongside
    { "originalError": { "data": revert.to_json() } },
  ]
  for data in shapes {
    inspect(
      ProviderError::from_code(3, "execution reverted", data~),
      content=(
        #|Reverted(code=3, message="execution reverted", data=0x08c379a0)
      ),
    )
  }
}

///|
/// A `data` that is no revert leaves the error exactly as it was: the shapes
/// above are read, not assumed.
test "from_code keeps Rpc when data carries no revert" {
  let not_revert : Array[Json] = [
    Json::null(),
    "not hex".to_json(),
    // hex, but an odd number of digits — no node ever wrote this
    "0x123".to_json(),
    { "other": "0x08c379a0".to_json() },
    Json::number(3),
  ]
  for data in not_revert {
    inspect(
      ProviderError::from_code(3, "execution reverted", data~),
      content=(
        #|Rpc(code=3, message="execution reverted")
      ),
    )
  }
}

///|
/// A code that already means something keeps its meaning: a wallet that
/// attaches `data` to a rejected prompt has still had the prompt rejected.
test "from_code prefers the code it knows over the data" {
  inspect(
    ProviderError::from_code(4001, "rejected", data="0x08c379a0".to_json()),
    content="UserRejected",
  )
}

///|
/// `Show` renders each variant compactly.
test "ProviderError show" {
  inspect("\{@provider.UserRejected}", content="UserRejected")
  inspect("\{@provider.UnrecognizedChain}", content="UnrecognizedChain")
  inspect("\{@provider.NotInstalled}", content="NotInstalled")
  inspect(
    "\{@provider.Rpc(code=-32603, message="boom")}",
    content=(
      #|Rpc(code=-32603, message="boom")
    ),
  )
  let data = @types.Hex::from_string("0x08c379a0") catch {
    e => fail("bad revert data: \{e}")
  }
  inspect(
    "\{@provider.Reverted(code=3, message="execution reverted", data~)}",
    content=(
      #|Reverted(code=3, message="execution reverted", data=0x08c379a0)
    ),
  )
}
