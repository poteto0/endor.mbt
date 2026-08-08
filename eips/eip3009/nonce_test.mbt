///|
/// Every fixture in `authorization_test.mbt` is signed against a fixed nonce,
/// because the hashes are. This is the one place the 32 bytes come from where
/// they come from in production.
test "draw_nonce" {
  let nonce = @eip3009.draw_nonce()
  // `Authorization::new` enforces `bytes32`, so a draw goes straight in
  let auth = @eip3009.Authorization::new(
    from=alice(),
    to=bob(),
    value=1000000,
    valid_before=2000000000,
    nonce~,
  )
  inspect(auth.nonce().byte_length(), content="32")
  // drawn rather than derived, so several can be in flight at once
  assert_not_eq(@eip3009.draw_nonce(), nonce)
}
