///|
test "which methods are sent at most once" {
  let sent_once = [
    "eth_sendTransaction", "eth_requestAccounts", "personal_sign", "eth_signTypedData_v4",
    "wallet_switchEthereumChain",
  ]
  for method_name in sent_once {
    assert_true(is_not_idempotent(method_name))
  }
  // already signed, so a resend is the same bytes and the same hash
  assert_false(is_not_idempotent("eth_sendRawTransaction"))
  assert_false(is_not_idempotent("eth_blockNumber"))
}
