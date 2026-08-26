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

///|
/// Anvil's second account authorizing `RECIPIENT` on mainnet — it is its own
/// authority — signed the way the account itself would.
fn a_signed_auth() -> @types.SignedAuthorization raise {
  sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::new(
      chain_id=@types.ChainId::mainnet(),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(1),
    ),
  )
}

///|
/// The six-field object an `authorizationList` is made of. Tests below mutate a
/// copy of it, so what each of them is about is the field it changed.
fn an_auth_json() -> Map[String, Json] {
  {
    "chainId": "0x1".to_json(),
    "address": RECIPIENT.to_lower().to_json(),
    "nonce": "0x1".to_json(),
    "yParity": "0x1".to_json(),
    "r": "0x1".to_json(),
    "s": "0x2".to_json(),
  }
}

///|
/// Decode an authorization built from `an_auth_json()` with `edits` applied.
fn signed_with(
  edits : Map[String, Json],
) -> @types.SignedAuthorization raise @types.CodecError {
  let fields = an_auth_json()
  for name, value in edits {
    fields[name] = value
  }
  @types.SignedAuthorization::from_json(Json::object(fields))
}

///|
/// The authority is nowhere in the authorization's fields: it comes back out of
/// the signature, and that is the only way to tell whose delegation this is.
test "the authority is recovered from the signature" {
  assert_eq(a_signed_auth().authority(), @types.Address::from_string(RECIPIENT))
}

///|
/// Recovery is not verification: it answers with whoever signed these bytes, so
/// the same authorization signed by another key is another delegation.
test "another key is another authority" {
  let authorization = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address=@types.Address::from_string(RECIPIENT),
    nonce=@types.Quantity::new(1),
  )
  assert_not_eq(
    sign_auth(ANVIL_KEY, authorization).authority(),
    sign_auth(ANVIL_KEY_1, authorization).authority(),
  )
}

///|
/// The shape `eth_sendTransaction` takes and a node answers with, both ways.
test "a signed authorization round-trips through JSON" {
  let signed = a_signed_auth()
  assert_eq(@types.SignedAuthorization::from_json(signed.to_json()), signed)
}

///|
/// A node is free to trim the leading zeros off `r` and `s`; the word they
/// denote is what the authorization carries.
test "a trimmed signature half is read as the word it denotes" {
  let expected = an_auth_json()
  expected["r"] = "0x0000000000000000000000000000000000000000000000000000000000000001".to_json()
  expected["s"] = "0x0000000000000000000000000000000000000000000000000000000000000002".to_json()
  assert_eq(signed_with({}).to_json(), Json::object(expected))
}

///|
/// Chain id `0` is refused on the way out and read on the way in: an
/// every-chain authorization a node reports is still an authorization.
test "chain 0 decodes as the every-chain authorization" {
  let signed = signed_with({
    "chainId": "0x0".to_json(),
    "nonce": "0x7".to_json(),
  })
  assert_eq(
    signed.authorization(),
    @types.Authorization::any_chain(
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(7),
    ),
  )
}

///|
/// A `v` of 27 or 28 belongs to a legacy transaction, not to an authorization,
/// and neither does a recovery id past the parity bit. Nor does a value that
/// would wrap into a bit on its way to an `Int`.
test "a y parity that is not a bit is refused" {
  for parity in ["0x2", "0x1b", "0x100000000"] {
    try signed_with({ "yParity": parity.to_json() }) |> ignore catch {
      InvalidValue(_) => ()
      e => fail("expected an invalid value, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  }
}

///|
/// `r` and `s` are words: something wider is not a signature this can carry.
test "a signature half wider than a word is refused" {
  try signed_with({ "r": ("0x" + "11".repeat(33)).to_json() }) |> ignore catch {
    InvalidLength(_) => ()
    e => fail("expected an invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
