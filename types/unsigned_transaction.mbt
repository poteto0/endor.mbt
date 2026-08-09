///|
/// The type byte an EIP-1559 transaction is introduced by (EIP-2718).
const EIP1559_TYPE : Byte = 0x02

///|
/// A transaction with everything filled in, ready to be signed.
///
/// This is the other half of `TransactionRequest`. That one is what a dapp
/// hands a *wallet*, so it leaves out what the wallet is expected to decide —
/// the nonce, the gas, often the fees. This one is what gets hashed: nothing
/// may be left open, because every field is part of what the signature commits
/// to and a node recomputes the same bytes to check it.
///
/// EIP-1559 (type `0x02`) only. A legacy transaction is a different encoding
/// with a different digest rule, and nothing in this SDK creates one — the
/// fee-market choice already lives in `Fee`, where `Legacy` means "opt out",
/// and opting out of a signature format is not the same decision.
///
/// The access list is always empty. It is part of the signed bytes so it has
/// to be encoded, but nothing here builds one, and an empty list is what a
/// transaction that touches no pre-declared storage carries.
pub struct UnsignedTransaction {
  priv chain_id : ChainId
  priv nonce : Quantity
  priv max_priority_fee_per_gas : Wei
  priv max_fee_per_gas : Wei
  priv gas : Quantity
  priv to : Address?
  priv value : Wei
  priv data : Hex
}

///|
/// Build one. `to` is absent for a contract creation, which is the only thing
/// an empty recipient means.
///
/// ```
/// let tx = @types.UnsignedTransaction::new(
///   chain_id=@types.ChainId::mainnet(),
///   nonce=@types.Quantity::new(0),
///   max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
///   max_fee_per_gas=@types.Wei::from_gwei("20"),
///   gas=@types.Quantity::new(21000),
///   to=@types.Address::from_string("0x0000000000000000000000000000000000000000"),
///   value=@types.Wei::from_ether("1"),
/// )
/// assert_eq(tx.signing_digest().length(), 32)
/// ```
pub fn UnsignedTransaction::new(
  chain_id~ : ChainId,
  nonce~ : Quantity,
  max_priority_fee_per_gas~ : Wei,
  max_fee_per_gas~ : Wei,
  gas~ : Quantity,
  to? : Address,
  value? : Wei = Wei::zero(),
  data? : Hex = Hex::from_bytes(b""),
) -> UnsignedTransaction {
  {
    chain_id,
    nonce,
    max_priority_fee_per_gas,
    max_fee_per_gas,
    gas,
    to,
    value,
    data,
  }
}

///|
/// The nine fields the signature commits to, in the order EIP-1559 fixes.
/// Order is the whole of what says which field is which — RLP carries no
/// names — so this list is the format.
fn UnsignedTransaction::fields(self : UnsignedTransaction) -> Array[@rlp.Item] {
  [
    @rlp.Item::of_uint64(self.chain_id.to_uint64()),
    @rlp.Item::of_uint64(self.nonce.to_uint64()),
    @rlp.Item::of_bigint(self.max_priority_fee_per_gas.to_bigint()),
    @rlp.Item::of_bigint(self.max_fee_per_gas.to_bigint()),
    @rlp.Item::of_uint64(self.gas.to_uint64()),
    // No recipient is the empty string, not a run of zero bytes: a transaction
    // to the zero address is a different transaction from a contract creation.
    match self.to {
      Some(to) => Bytes(@codec.bytes_of_digits(to.digits()))
      None => Bytes(b"")
    },
    @rlp.Item::of_bigint(self.value.to_bigint()),
    Bytes(self.data.to_bytes()),
    // The access list, always empty. See the type.
    List([]),
  ]
}

///|
/// What to sign: `keccak256(0x02 || rlp(fields))`.
///
/// The type byte is outside the RLP, which is what EIP-2718 introduced — an
/// envelope, so that a new transaction format needs a new byte rather than a
/// new way to tell lists apart.
pub fn UnsignedTransaction::signing_digest(self : UnsignedTransaction) -> Bytes {
  @keccak.keccak256(
    Bytes::make(1, EIP1559_TYPE) + @rlp.encode(List(self.fields())),
  )
}

///|
/// The transaction as it goes to `eth_sendRawTransaction`: the same fields
/// again with the signature appended, under the same type byte.
///
/// Takes the signature in parts rather than a `Signature`, so this package
/// stays independent of the curve that produced it: `r` and `s` big-endian in
/// 32 bytes, and `y_parity` the recovery id.
///
/// Raises if `y_parity` is not 0 or 1. A recovery id of 2 or 3 says the
/// signature's `r` wrapped past the group order, which no Ethereum transaction
/// can carry — a node has nowhere to put the missing bit.
pub fn UnsignedTransaction::encode_signed(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Hex raise CodecError {
  guard y_parity == 0 || y_parity == 1 else {
    raise InvalidValue("y parity must be 0 or 1: \{y_parity}")
  }
  let fields = self.fields()
  fields.push(@rlp.Item::of_uint64(y_parity.to_uint64()))
  fields.push(@rlp.Item::of_bigint(@bigint.BigInt::from_octets(r[:])))
  fields.push(@rlp.Item::of_bigint(@bigint.BigInt::from_octets(s[:])))
  Hex::from_bytes(Bytes::make(1, EIP1559_TYPE) + @rlp.encode(List(fields)))
}

///|
/// The hash the transaction will be known by once it is broadcast: the
/// Keccak-256 of exactly the bytes `encode_signed` produces.
pub fn UnsignedTransaction::hash(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> TxHash raise CodecError {
  TxHash::from_string(
    "0x" +
    @codec.digits_of_bytes(
      @keccak.keccak256(self.encode_signed(r~, s~, y_parity~).to_bytes()),
    ),
  )
}
