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
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(ANVIL_KEY))
  let signature = key.sign(tx.signing_digest())
  tx
  .encode_signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  )
  .to_string()
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
