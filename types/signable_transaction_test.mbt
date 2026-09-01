///|
/// One of each envelope, the legacy form included — its digest and its `v` are
/// the two places the chain id is not just another field.
fn every_envelope() -> Array[@types.UnsignedTransaction] raise {
  [
    @types.UnsignedTransaction::new(
      chain_id=@types.ChainId::mainnet(),
      nonce=@types.Quantity::new(0),
      max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      max_fee_per_gas=@types.Wei::from_gwei("20"),
      gas=@types.Quantity::new(21000),
      to=@types.Address::from_string(RECIPIENT),
      value=@types.Wei::from_ether("1"),
      access_list=[a_recipient_entry()],
    ),
    @types.UnsignedTransaction::eip2930(
      chain_id=@types.ChainId::mainnet(),
      nonce=@types.Quantity::new(0),
      gas_price=@types.Wei::from_gwei("20"),
      gas=@types.Quantity::new(21000),
      to=@types.Address::from_string(RECIPIENT),
      value=@types.Wei::from_ether("1"),
      access_list=[a_recipient_entry()],
    ),
    a_legacy_transfer(),
    @types.UnsignedTransaction::eip7702(
      chain_id=@types.ChainId::mainnet(),
      nonce=@types.Quantity::new(0),
      max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      max_fee_per_gas=@types.Wei::from_gwei("20"),
      gas=@types.Quantity::new(100000),
      to=@types.Address::from_string(ANVIL_ADDRESS),
      authorization_list=[a_signed_auth()],
    ),
  ]
}

///|
/// The whole of what the change is allowed to do is cost less. Every vector in
/// `unsigned_transaction_test.mbt` asks the transaction itself, so this is what
/// says the built-once path answers the same.
test "a signable answers what the transaction answers" {
  for tx in every_envelope() {
    let signable = tx.signable()
    assert_eq(signable.signing_digest(), tx.signing_digest())
    let signature = signed_by_anvil(tx)
    let r = signature.r()
    let s = signature.s()
    let y_parity = signature.recovery_id()
    assert_eq(
      signable.encode_signed(r~, s~, y_parity~),
      tx.encode_signed(r~, s~, y_parity~),
    )
    assert_eq(signable.hash(r~, s~, y_parity~), tx.hash(r~, s~, y_parity~))
  }
}

///|
/// Nothing a question appends may stay on the fields — a signature, or the
/// `[chain_id, 0, 0]` a legacy digest signs.
test "a signable can be asked twice" {
  for tx in every_envelope() {
    let signable = tx.signable()
    let signature = signed_by_anvil(tx)
    let r = signature.r()
    let s = signature.s()
    let y_parity = signature.recovery_id()
    let digest = signable.signing_digest()
    let raw = signable.encode_signed(r~, s~, y_parity~)
    assert_eq(signable.encode_signed(r~, s~, y_parity~), raw)
    assert_eq(signable.signing_digest(), digest)
  }
}
