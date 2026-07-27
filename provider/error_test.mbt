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
}
