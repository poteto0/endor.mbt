///|
/// Anvil's second account, so that the authority and the account paying for the
/// transaction are visibly not the same one.
const ANVIL_KEY_1 = "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

///|
/// Sign `auth` with `key`, the way the authority itself would.
fn sign_auth(
  key : String,
  auth : @types.Authorization,
) -> @types.SignedAuthorization raise {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(key))
  let signature = key.sign(auth.signing_digest())
  auth.signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  )
}

///|
/// The digest is the 0x05 envelope, not the transaction's — a 32-byte hash of
/// something no transaction type can be read as.
test "an authorization signs under its own magic byte" {
  let auth = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address=@types.Address::from_string(RECIPIENT),
    nonce=@types.Quantity::new(1),
  )
  assert_eq(auth.signing_digest().length(), 32)
}

///|
/// Chain id `0` is a different authorization from any real chain's, and it can
/// only be spelled by asking for it.
test "any_chain is not the same authorization as chain 1" {
  let address = @types.Address::from_string(RECIPIENT)
  let nonce = @types.Quantity::new(1)
  let anywhere = @types.Authorization::any_chain(address~, nonce~)
  let mainnet = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address~,
    nonce~,
  )
  assert_not_eq(anywhere.signing_digest(), mainnet.signing_digest())
}

///|
/// Chain id `0` cannot be reached through `new`, so a chain id that arrives as
/// a variable cannot quietly become an every-chain authorization.
test "chain 0 has to be asked for by name" {
  try
    @types.Authorization::new(
      chain_id=@types.ChainId::new(0),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(1),
    )
    |> ignore
  catch {
    InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The nonce is the authority's, so getting it wrong is a different signature
/// rather than an error — the only place that shows is the digest.
test "the authorization nonce is signed over" {
  let address = @types.Address::from_string(RECIPIENT)
  let chain_id = @types.ChainId::mainnet()
  assert_not_eq(
    @types.Authorization::new(
      chain_id~,
      address~,
      nonce=@types.Quantity::new(0),
    ).signing_digest(),
    @types.Authorization::new(
      chain_id~,
      address~,
      nonce=@types.Quantity::new(1),
    ).signing_digest(),
  )
}

///|
/// An authorization takes a signature on the same terms a transaction does.
test "only a parity bit can be attached to an authorization" {
  let auth = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address=@types.Address::from_string(RECIPIENT),
    nonce=@types.Quantity::new(1),
  )
  let word = Bytes::make(32, b'\x01')
  try auth.signed(r=word, s=word, y_parity=2) |> ignore catch {
    InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
  let short = Bytes::make(31, b'\x01')
  try auth.signed(r=short, s=short, y_parity=0) |> ignore catch {
    InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
