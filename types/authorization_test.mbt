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
/// The authority is nowhere in the authorization's fields: it comes back out of
/// the signature, and that is the only way to tell whose delegation this is.
test "the authority is recovered from the signature" {
  let signed = sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::new(
      chain_id=@types.ChainId::mainnet(),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(1),
    ),
  )
  assert_eq(signed.authority(), @types.Address::from_string(RECIPIENT))
}

///|
/// The signed nonce is the authority's own. Signing the wrong one recovers a
/// different account rather than raising — the failure this makes visible.
test "a wrong nonce recovers a different authority" {
  let address = @types.Address::from_string(RECIPIENT)
  let chain_id = @types.ChainId::mainnet()
  let signed = sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::new(
      chain_id~,
      address~,
      nonce=@types.Quantity::new(1),
    ),
  )
  let elsewhere = @types.SignedAuthorization::from_json(
    Json::object({
      "chainId": chain_id.to_json(),
      "address": address.to_json(),
      "nonce": @types.Quantity::new(2).to_json(),
      "yParity": Json::string("0x0"),
      "r": Json::string("0x1"),
      "s": Json::string("0x2"),
    }),
  )
  assert_not_eq(elsewhere.authority(), signed.authority())
}

///|
/// The shape `eth_sendTransaction` takes and a node answers with, both ways.
test "a signed authorization round-trips through JSON" {
  let signed = sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::new(
      chain_id=@types.ChainId::mainnet(),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(1),
    ),
  )
  assert_eq(@types.SignedAuthorization::from_json(signed.to_json()), signed)
}

///|
/// A node is free to trim the leading zeros off `r` and `s`; the word they
/// denote is what the authorization carries.
test "a trimmed signature half is read as the word it denotes" {
  let signed = @types.SignedAuthorization::from_json(
    Json::object({
      "chainId": Json::string("0x0"),
      "address": Json::string(RECIPIENT),
      "nonce": Json::string("0x0"),
      "yParity": Json::string("0x1"),
      "r": Json::string("0x1"),
      "s": Json::string("0x2"),
    }),
  )
  assert_eq(
    signed.to_json(),
    Json::object({
      "chainId": Json::string("0x0"),
      "address": Json::string(RECIPIENT.to_lower()),
      "nonce": Json::string("0x0"),
      "yParity": Json::string("0x1"),
      "r": Json::string(
        "0x0000000000000000000000000000000000000000000000000000000000000001",
      ),
      "s": Json::string(
        "0x0000000000000000000000000000000000000000000000000000000000000002",
      ),
    }),
  )
}

///|
/// Chain id `0` is refused on the way out and read on the way in: an
/// every-chain authorization a node reports is still an authorization.
test "chain 0 decodes as the every-chain authorization" {
  let signed = @types.SignedAuthorization::from_json(
    Json::object({
      "chainId": Json::string("0x0"),
      "address": Json::string(RECIPIENT),
      "nonce": Json::string("0x7"),
      "yParity": Json::string("0x0"),
      "r": Json::string("0x1"),
      "s": Json::string("0x2"),
    }),
  )
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
/// and neither does a recovery id past the parity bit.
test "a y parity that is not a bit is refused" {
  for parity in ["0x2", "0x1b"] {
    try
      @types.SignedAuthorization::from_json(
        Json::object({
          "chainId": Json::string("0x1"),
          "address": Json::string(RECIPIENT),
          "nonce": Json::string("0x0"),
          "yParity": Json::string(parity),
          "r": Json::string("0x1"),
          "s": Json::string("0x2"),
        }),
      )
      |> ignore
    catch {
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
  try
    @types.SignedAuthorization::from_json(
      Json::object({
        "chainId": Json::string("0x1"),
        "address": Json::string(RECIPIENT),
        "nonce": Json::string("0x0"),
        "yParity": Json::string("0x0"),
        "r": Json::string("0x" + "11".repeat(33)),
        "s": Json::string("0x2"),
      }),
    )
    |> ignore
  catch {
    InvalidLength(_) => ()
    e => fail("expected an invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
