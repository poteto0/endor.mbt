///|
/// Anvil's first account, whose key every Ethereum toolchain ships as a test
/// fixture. Its address is checked below, so a wrong key cannot quietly make
/// the rest of these vectors pass.
const ANVIL_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

///|
const ANVIL_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

///|
const RECIPIENT = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

///|
/// Sign `tx` with the anvil key and return the bytes `eth_sendRawTransaction`
/// would take. Every vector below came out of `cast mktx`, so what these
/// compare against is Foundry's encoder and Foundry's signer.
fn raw(tx : @types.UnsignedTransaction) -> String raise {
  let signature = signed_by_anvil(tx)
  tx
  .encode_signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  )
  .to_string()
}

///|
/// The anvil key's signature over what `tx` says to sign.
fn signed_by_anvil(
  tx : @types.UnsignedTransaction,
) -> @secp256k1.Signature raise {
  @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(ANVIL_KEY)).sign(
    tx.signing_digest(),
  )
}

///|
/// The mainnet transfer the legacy tests below are all about.
fn a_legacy_transfer() -> @types.UnsignedTransaction raise {
  @types.UnsignedTransaction::legacy(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    gas_price=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string(RECIPIENT),
    value=@types.Wei::from_ether("1"),
  )
}

///|
/// The key is the one the vectors were made with.
test "the anvil key is the anvil account" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(ANVIL_KEY))
  assert_eq(
    @types.Address::from_public_key(key.public_key()).to_checksum_string(),
    ANVIL_ADDRESS,
  )
}

///|
/// A plain transfer: `cast mktx --chain 1 --nonce 0 --gas-limit 21000
/// --priority-gas-price 1gwei --gas-price 20gwei --value 1ether`.
test "a plain transfer matches cast mktx" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string(RECIPIENT),
    value=@types.Wei::from_ether("1"),
  )
  assert_eq(
    raw(tx),
    "0x02f8730180843b9aca008504a817c8008252089470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a00a3a2646d4ad968bb56317fdb15e17fb4d9deec0d03e8b6cb05e7125bda3006da026618ad17cc63cf1979ca75f850c536a073ec88ab1ab7c8db8b8eb129499d9ae",
  )
}

///|
/// The hash a node will know that transaction by.
test "the transaction hash is the hash of those bytes" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string(RECIPIENT),
    value=@types.Wei::from_ether("1"),
  )
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(ANVIL_KEY))
  let signature = key.sign(tx.signing_digest())
  assert_eq(
    tx
    .hash(r=signature.r(), s=signature.s(), y_parity=signature.recovery_id())
    .to_string(),
    "0x9bab8d3e7893fd77088c164d2834ddcb9fbfa73c93bdee90e396e3e27141f1ba",
  )
}

///|
/// Calldata, a nonce that is not zero, and a chain id too wide for one byte —
/// three fields that each have a different length form in RLP.
test "a call with data matches cast mktx" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::new(31337),
    nonce=@types.Quantity::new(7),
    max_priority_fee_per_gas=@types.Wei::from_gwei("2"),
    max_fee_per_gas=@types.Wei::from_gwei("30"),
    gas=@types.Quantity::new(100000),
    to=@types.Address::from_string(RECIPIENT),
    data=@types.Hex::from_string(
      "0xa9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000000000000000000000000000016345785d8a0000",
    ),
  )
  assert_eq(
    raw(tx),
    "0x02f8b3827a690784773594008506fc23ac00830186a09470997970c51812dc3a010c7d01b50e0d17dc79c880b844a9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000000000000000000000000000016345785d8a0000c080a06e1fd0d9b1ec0adc6260e23075e10567e148706309be953ac353cc263dd54c2aa0772699b2afa622b66488d911c1fd837e5b5246f05918e702d451f3dd1b80793c",
  )
}

///|
/// No recipient: a contract creation, where `to` encodes as the empty string.
test "a contract creation matches cast mktx" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(1),
    max_priority_fee_per_gas=@types.Wei::from_int(1),
    max_fee_per_gas=@types.Wei::from_gwei("1"),
    gas=@types.Quantity::new(500000),
    data=@types.Hex::from_string("0x60806040"),
  )
  assert_eq(
    raw(tx),
    "0x02f857010101843b9aca008307a12080808460806040c001a08e80361cae292803fac16b593611c2190108d307d81658d6520e0999a72e16c9a07e9d407d5306f11b734867e1db79de6819a033d642f37b8de18babb0915dcc13",
  )
}

///|
/// A transaction to the zero address is not a contract creation, even though
/// both look like "no recipient" at a glance. RLP tells them apart by the
/// empty string, so this is the one place the distinction is visible.
test "the zero address is not a contract creation" {
  let fields = (
    @types.ChainId::mainnet(),
    @types.Quantity::new(1),
    @types.Wei::from_int(1),
    @types.Wei::from_gwei("1"),
    @types.Quantity::new(500000),
  )
  let (chain_id, nonce, tip, cap, gas) = fields
  let creation = @types.UnsignedTransaction::new(
    chain_id~,
    nonce~,
    max_priority_fee_per_gas=tip,
    max_fee_per_gas=cap,
    gas~,
  )
  let to_zero = @types.UnsignedTransaction::new(
    chain_id~,
    nonce~,
    max_priority_fee_per_gas=tip,
    max_fee_per_gas=cap,
    gas~,
    to=@types.Address::from_string("0x0000000000000000000000000000000000000000"),
  )
  assert_not_eq(creation.signing_digest(), to_zero.signing_digest())
}

///|
/// A recovery id of 2 or 3 says `r` wrapped past the group order, which no
/// Ethereum transaction can carry.
test "only a parity bit can be encoded" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string(RECIPIENT),
  )
  let word = Bytes::make(32, b'\x01')
  try tx.encode_signed(r=word, s=word, y_parity=2) |> ignore catch {
    InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "r and s must be 32 bytes each" {
  let tx = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(21000),
    to=@types.Address::from_string(RECIPIENT),
  )
  let word = Bytes::make(31, b'\x01') // 31 bytes instead of 32
  try tx.encode_signed(r=word, s=word, y_parity=0) |> ignore catch {
    InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The legacy form of the first vector: `cast mktx --legacy --chain 1 --nonce 0
/// --gas-limit 21000 --gas-price 20gwei --value 1ether`. No type byte, six
/// fields, and `v` of 38 — parity 1 with chain id 1 folded in.
test "a legacy transfer matches cast mktx" {
  let tx = a_legacy_transfer()
  assert_eq(
    raw(tx),
    "0xf86c808504a817c8008252089470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a76400008026a07229466cbc255807f150595728b381915b4863bb0bae6acd1be795ed359f2146a07936385b6c8bdece4255eb135ad8f8bc1d5f35e54582685f59535a92bfb80369",
  )
}

///|
/// The hash a node will know that transaction by.
test "the legacy transaction hash is the hash of those bytes" {
  let tx = a_legacy_transfer()
  let signature = signed_by_anvil(tx)
  assert_eq(
    tx
    .hash(r=signature.r(), s=signature.s(), y_parity=signature.recovery_id())
    .to_string(),
    "0x8368128483347693143d67793f7d4c58c23c4ee22ffdc2698b1fe75bc8375c56",
  )
}

///|
/// A chain id too wide for one byte, so that `v` is a two-byte number rather
/// than the 37 or 38 mainnet makes it: 31337 * 2 + 35 + 1 = 62710.
test "a legacy call with data matches cast mktx" {
  let tx = @types.UnsignedTransaction::legacy(
    chain_id=@types.ChainId::new(31337),
    nonce=@types.Quantity::new(7),
    gas_price=@types.Wei::from_gwei("30"),
    gas=@types.Quantity::new(100000),
    to=@types.Address::from_string(RECIPIENT),
    data=@types.Hex::from_string(
      "0xa9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000000000000000000000000000016345785d8a0000",
    ),
  )
  assert_eq(
    raw(tx),
    "0xf8ac078506fc23ac00830186a09470997970c51812dc3a010c7d01b50e0d17dc79c880b844a9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000000000000000000000000000016345785d8a000082f4f6a0cda313c39c477978d43964cd09adcf10f7d1837b8eaad217e9719be6a819e98ea07f2e3e4aa870febf665a82195ce7047f5b4e684dc9933934fadf604e259924e4",
  )
}

///|
/// No recipient, the legacy way: `to` is the empty string here too.
test "a legacy contract creation matches cast mktx" {
  let tx = @types.UnsignedTransaction::legacy(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(1),
    gas_price=@types.Wei::from_gwei("1"),
    gas=@types.Quantity::new(500000),
    data=@types.Hex::from_string("0x60806040"),
  )
  assert_eq(
    raw(tx),
    "0xf85401843b9aca008307a1208080846080604025a0ee28ae4045a4f13ded27817ae409196ce9965eb97cb7801529aa3081088bd3baa00cd5daaca45549b4462402bf6787646a8aeaae53b55325171d296ed8fdfabcdf",
  )
}

///|
/// A legacy transaction asks the wallet for the same thing it would sign: a
/// flat `gasPrice`, and no EIP-1559 pair.
test "a legacy transaction asks a wallet for a flat price" {
  let tx = a_legacy_transfer()
  inspect(
    tx
    .to_request(from=@types.Address::from_string(ANVIL_ADDRESS))
    .unwrap()
    .to_json()
    .stringify(),
    content=(
      #|{"from":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266","to":"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","value":"0xde0b6b3a7640000","data":"0x","gas":"0x5208","nonce":"0x0","gasPrice":"0x4a817c800"}
    ),
  )
}

///|
/// A 7702 transaction with one authorization, whose authority is a different
/// account from the one paying: `cast wallet sign-auth 0x7099… --nonce 1
/// --chain 1` for the authorization, then `cast mktx --auth`.
test "a 7702 transaction matches cast mktx" {
  let auth = sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::new(
      chain_id=@types.ChainId::mainnet(),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(1),
    ),
  )
  let tx = @types.UnsignedTransaction::eip7702(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(100000),
    to=@types.Address::from_string(ANVIL_ADDRESS),
    authorization_list=[auth],
  )
  assert_eq(
    raw(tx),
    "0x04f8ca0180843b9aca008504a817c800830186a094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0f85cf85a019470997970c51812dc3a010c7d01b50e0d17dc79c80180a0c26a31db6ecf06b8ca99a9d25a1e31862d176d650e3bd499f5a693168a9dddc4a02e40c9fd48589607d2b6bf79d3a3c8792abb47a721c419d2c24d061e7683e3be01a0e688f81f5d87b70b2f351037c5fd5b37b5577388634a11aac97c4cd2cd8682a9a025e71c841b17aaeffa341ab173ccef4c927a810d2a3f2a7bfb4b523cc2960cd1",
  )
}

///|
/// Two authorizations, one of them a chain-`0` revocation signed by another
/// account and the other the sender's own — the list is a list, the two
/// signatures land on opposite parities, and a revocation is just the zero
/// address.
test "a 7702 transaction carries a list of authorizations" {
  let revoke = sign_auth(
    ANVIL_KEY_1,
    @types.Authorization::any_chain(
      address=@types.Address::from_string(
        "0x0000000000000000000000000000000000000000",
      ),
      nonce=@types.Quantity::new(5),
    ),
  )
  let delegate = sign_auth(
    ANVIL_KEY,
    @types.Authorization::new(
      chain_id=@types.ChainId::new(31337),
      address=@types.Address::from_string(RECIPIENT),
      nonce=@types.Quantity::new(8),
    ),
  )
  let tx = @types.UnsignedTransaction::eip7702(
    chain_id=@types.ChainId::new(31337),
    nonce=@types.Quantity::new(7),
    max_priority_fee_per_gas=@types.Wei::from_gwei("2"),
    max_fee_per_gas=@types.Wei::from_gwei("30"),
    gas=@types.Quantity::new(200000),
    to=@types.Address::from_string(RECIPIENT),
    value=@types.Wei::from_ether("1"),
    authorization_list=[revoke, delegate],
  )
  assert_eq(
    raw(tx),
    "0x04f90132827a690784773594008506fc23ac0083030d409470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0f8baf85a809400000000000000000000000000000000000000000501a017f1385b31867f1358c2f28dd8da0339743b47bbd7f0058bd5f8ae05f3698243a03dfedbe14b158234789c1bf1af3e3084d3bd657b6d26b13d6244578d0a4f221cf85c827a699470997970c51812dc3a010c7d01b50e0d17dc79c80880a0568bae22f9b2574a1d956fe8e02d650720c1bb23a9688a02e126ccdcdd09b5fea058ed8b2ac70668ed897282df55527e15fed9713aa3a492a52a666f80d30f282201a037d1d23af8f7b21640c1946d6b5f81ece3e065988db832bc2290cc5b011d55f3a07d1fa5054c4c47ce6cb1d9cf06aff773d44230a0acee27bd7eb43a3e8ea9da09",
  )
  let signature = signed_by_anvil(tx)
  assert_eq(
    tx
    .hash(r=signature.r(), s=signature.s(), y_parity=signature.recovery_id())
    .to_string(),
    "0x6ace42546c673d43132899b483d22c3c31599ed981cedbfd109673dd9ad6a5c5",
  )
}

///|
/// A 7702 transaction that delegates nothing is not a 7702 transaction.
test "a 7702 transaction needs an authorization" {
  try
    @types.UnsignedTransaction::eip7702(
      chain_id=@types.ChainId::mainnet(),
      nonce=@types.Quantity::new(0),
      max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
      max_fee_per_gas=@types.Wei::from_gwei("20"),
      gas=@types.Quantity::new(100000),
      to=@types.Address::from_string(RECIPIENT),
      authorization_list=[],
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
/// The list is copied in, so emptying the caller's array afterwards cannot
/// leave a transaction the constructor would have refused.
test "the authorization list cannot be emptied afterwards" {
  let list = [
    sign_auth(
      ANVIL_KEY_1,
      @types.Authorization::new(
        chain_id=@types.ChainId::mainnet(),
        address=@types.Address::from_string(RECIPIENT),
        nonce=@types.Quantity::new(1),
      ),
    ),
  ]
  let tx = @types.UnsignedTransaction::eip7702(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(100000),
    to=@types.Address::from_string(ANVIL_ADDRESS),
    authorization_list=list,
  )
  let before = tx.signing_digest()
  list.clear()
  assert_eq(tx.signing_digest(), before)
}

///|
/// `eth_sendTransaction` has nowhere to put the authorization list, and sending
/// one without it would send a different transaction.
test "a 7702 transaction has no request form" {
  let tx = @types.UnsignedTransaction::eip7702(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(100000),
    to=@types.Address::from_string(RECIPIENT),
    authorization_list=[
      sign_auth(
        ANVIL_KEY_1,
        @types.Authorization::new(
          chain_id=@types.ChainId::mainnet(),
          address=@types.Address::from_string(RECIPIENT),
          nonce=@types.Quantity::new(1),
        ),
      ),
    ],
  )
  assert_true(
    tx.to_request(from=@types.Address::from_string(ANVIL_ADDRESS)) is None,
  )
}
