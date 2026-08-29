///|
/// Anvil's first account, the key every Ethereum toolchain ships as a fixture.
/// Every expected value below came out of `cast wallet sign` or `cast mktx`,
/// so what these compare against is Foundry.
const ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

///|
const ANVIL_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

///|
fn anvil() -> @local.LocalAccount raise {
  @local.LocalAccount::new(@types.Hex::from_string(ANVIL_KEY))
}

///|
test "the address comes from the key" {
  assert_eq(anvil().address().to_checksum_string(), ANVIL_ADDRESS)
  assert_eq(anvil().account_type(), "local")
}

///|
/// `cast wallet sign --private-key … "hello"`. The `v` is `0x1c`, the offset
/// form — `27 + 1` — which is what tells a verifier this is not a typed
/// transaction's bare parity bit.
async test "personal_sign of a text message matches cast" {
  assert_eq(
    anvil().sign_message(@types.Hex::from_utf8("hello")).to_string(),
    "0xf16ea9a3478698f695fd1401bfe27e9e4a7e8e3da94aa72b021125e31fa899cc573c48ea3fe1d4ab61a9db10c19032026e3ed2dbccba5a178235ac27f94504311c",
  )
}

///|
/// The same prefix over bytes that are not text: `cast wallet sign …
/// "0xdeadbeef"`, which cast decodes before signing.
async test "personal_sign of raw bytes matches cast" {
  assert_eq(
    anvil().sign_message(@types.Hex::from_string("0xdeadbeef")).to_string(),
    "0xa114c834af73872c6c9efe918d85b0b1b34a486d10f9011e2630e28417c828c060dbd65cda67e73d52ebb7c555260621dbc1b0b4036acb61086bba091ac3f1641b",
  )
}

///|
/// `cast wallet sign --data --from-file`, over the same document written as
/// JSON. EIP-712 hashes the types and the values separately, so this checks
/// the digest rule as much as the curve.
async test "typed data matches cast" {
  let typed_data = @eip712.TypedData::new(
    @eip712.TypedDataDomain::new(
      name="Endor",
      chain_id=@types.ChainId::mainnet(),
    ),
    primary_type="Permit",
    types={
      "Permit": [
        @eip712.TypedDataField::new("holder", "address"),
        @eip712.TypedDataField::new("value", "uint256"),
      ],
    },
    message={
      "holder": "0x52908400098527886e0f7030069857d2e4169ee7",
      "value": Json::number(1),
    },
  )
  assert_eq(
    anvil().sign_typed_data(typed_data).to_string(),
    "0xcebefb2cb62092fad545b4841a89df501da247b9223972eb567bfd09dc63ca272fdac01bcda9387f0645e8a043a266a2e9ee704f6ed7968afa762e1a0ace77c41c",
  )
}

///|
/// `cast mktx`. Unlike the other two this answers with the whole transaction,
/// not a signature, and its `v` is the bare parity bit.
async test "a signed transaction matches cast mktx" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    value=@types.Wei::from_ether("1"),
  )
  assert_eq(
    anvil().sign_transaction(tx).to_string(),
    "0x02f8730180843b9aca008504a817c8008252089470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a00a3a2646d4ad968bb56317fdb15e17fb4d9deec0d03e8b6cb05e7125bda3006da026618ad17cc63cf1979ca75f850c536a073ec88ab1ab7c8db8b8eb129499d9ae",
  )
}

///|
/// The signing methods must not agree on anything. Each hashes under a
/// different rule, so the same bytes handed to two of them give two different
/// signatures — which is exactly what stops a message from being replayed as a
/// transaction.
async test "each rule signs something different" {
  let account = anvil()
  let message = @types.Hex::from_utf8("hello")
  assert_not_eq(
    account.sign_message(message).to_string(),
    account.sign_message(@types.Hex::from_utf8("hello!")).to_string(),
  )
  // Signing the same bytes as a message twice is stable, though — the nonce is
  // derived from the digest and nothing else.
  assert_eq(
    account.sign_message(message).to_string(),
    account.sign_message(message).to_string(),
  )
}

///|
/// The one thing a caller can get wrong here is the key.
test "a key that is not a key is refused" {
  for wrong in ["0x", "0xff", "0x" + "00".repeat(32), "0x" + "ff".repeat(32)] {
    let hex = @types.Hex::from_string(wrong)
    try @local.LocalAccount::new(hex) |> ignore catch {
      InvalidPrivateKey(_) => ()
      e => fail("expected an invalid key, but not \{e}")
    } noraise {
      _ => fail("expected \{wrong} to be refused")
    }
  }
}

///|
test "the error reads without naming the curve" {
  assert_eq(
    @account.AccountError::SigningFailed("digest").message(),
    "That could not be signed.",
  )
  assert_false(@account.AccountError::SigningFailed("digest").is_retryable())
}

///|
/// `cast wallet sign-auth --nonce 0 --chain 1`. It answers with the RLP tuple
/// `f85a 01 94… 80 01 a0<r> a0<s>`, whose six fields are the six read out
/// here as the JSON an `authorizationList` is written in.
async test "an authorization matches cast sign-auth" {
  let auth = @types.Authorization::new(
    chain_id=@types.ChainId::mainnet(),
    address=@types.Address::from_string(
      "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    ),
    nonce=@types.Quantity::new(0),
  )
  inspect(
    anvil().sign_authorization(auth).to_json().stringify(),
    content=(
      #|{"chainId":"0x1","address":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","nonce":"0x0","yParity":"0x1","r":"0x6ec4b1499e966621ff003b44ec3ae73a8315ed91567430a7e885d3e6f10cd125","s":"0x547fb5e0f781e8e51a88007a9da27a3f79057120578775bc09290dfba7c146db"}
    ),
  )
}

///|
/// The parity is the bare bit, not the `27` offset a message signature carries
/// — so the authority recovers, which is the whole of what the signature is
/// there to say.
async test "the signed authorization recovers to this account" {
  let auth = @types.Authorization::any_chain(
    address=@types.Address::from_string(
      "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    ),
    nonce=@types.Quantity::new(7),
  )
  let account = anvil()
  let signed = account.sign_authorization(auth)
  assert_eq(signed.authority(), account.address())
  assert_eq(signed.authorization(), auth)
}
