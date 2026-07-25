///|
/// Exhaustive check of EIP-1193 / EIP-1474 code -> variant mapping.
test "from_code maps standard EIP-1193 codes" {
  assert_eq(ProviderError::from_code(4001, ""), UserRejected)
  assert_eq(ProviderError::from_code(4100, ""), Unauthorized)
  assert_eq(ProviderError::from_code(4200, ""), UnsupportedMethod)
  assert_eq(ProviderError::from_code(4900, ""), Disconnected)
  assert_eq(ProviderError::from_code(4901, ""), ChainDisconnected)
  assert_eq(ProviderError::from_code(4902, ""), UnrecognizedChain)
}

///|
/// Unknown codes fall through to the generic `Rpc` variant, preserving code
/// and message.
test "from_code falls through to Rpc" {
  assert_eq(
    ProviderError::from_code(-32603, "internal"),
    Rpc(code=-32603, message="internal"),
  )
  assert_eq(
    ProviderError::from_code(-32000, "revert"),
    Rpc(code=-32000, message="revert"),
  )
  assert_eq(ProviderError::from_code(0, "?"), Rpc(code=0, message="?"))
}

///|
/// `Show` renders each variant compactly.
test "ProviderError show" {
  assert_eq("\{@provider.UserRejected}", "UserRejected")
  assert_eq("\{@provider.UnrecognizedChain}", "UnrecognizedChain")
  assert_eq("\{@provider.NotInstalled}", "NotInstalled")
  assert_eq(
    "\{@provider.Rpc(code=-32603, message="boom")}",
    "Rpc(code=-32603, message=\"boom\")",
  )
}
