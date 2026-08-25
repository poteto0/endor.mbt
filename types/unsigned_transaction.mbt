///|
/// A transaction with everything filled in, ready to be signed — the other half
/// of `TransactionRequest`. Nothing may be left open, because every field is
/// part of what the signature commits to.
///
/// One variant per EIP-2718 transaction type, plus the legacy form that
/// predates the envelope. EIP-1559's access list is always empty: it is part of
/// the signed bytes, but nothing here builds one.
pub enum UnsignedTransaction {
  Eip1559(
    chain_id~ : ChainId,
    nonce~ : Quantity,
    max_priority_fee_per_gas~ : Wei,
    max_fee_per_gas~ : Wei,
    gas~ : Quantity,
    to~ : Address?,
    value~ : Wei,
    data~ : Hex
  )
  /// The pre-EIP-2718 form, for a chain with no EIP-1559 market. The chain id
  /// is not a field of it: EIP-155 folds it into the signature instead.
  Legacy(
    chain_id~ : ChainId,
    nonce~ : Quantity,
    gas_price~ : Wei,
    gas~ : Quantity,
    to~ : Address?,
    value~ : Wei,
    data~ : Hex
  )
}

///|
/// Build an EIP-1559 transaction. `to` is absent for a contract creation, which
/// is the only thing an empty recipient means.
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
  Eip1559(
    chain_id~,
    nonce~,
    max_priority_fee_per_gas~,
    max_fee_per_gas~,
    gas~,
    to~,
    value~,
    data~,
  )
}

///|
/// Build a legacy transaction, for a chain that never forked to London or a
/// node that reports no base fee. Everything else is `new`'s.
///
/// The signature is always EIP-155's, so the transaction is replayable on no
/// other chain. A pre-155 transaction — `v` of 27 or 28, bound to nothing —
/// cannot be built here on purpose.
///
/// ```
/// let tx = @types.UnsignedTransaction::legacy(
///   chain_id=@types.ChainId::new(56),
///   nonce=@types.Quantity::new(0),
///   gas_price=@types.Wei::from_gwei("5"),
///   gas=@types.Quantity::new(21000),
///   to=@types.Address::from_string("0x0000000000000000000000000000000000000000"),
///   value=@types.Wei::from_ether("1"),
/// )
/// assert_eq(tx.signing_digest().length(), 32)
/// ```
pub fn UnsignedTransaction::legacy(
  chain_id~ : ChainId,
  nonce~ : Quantity,
  gas_price~ : Wei,
  gas~ : Quantity,
  to? : Address,
  value? : Wei = Wei::zero(),
  data? : Hex = Hex::from_bytes(b""),
) -> UnsignedTransaction {
  Legacy(chain_id~, nonce~, gas_price~, gas~, to~, value~, data~)
}

///|
/// The type byte EIP-2718 introduces the transaction by. A legacy transaction
/// has none, which is what `None` is for.
fn UnsignedTransaction::type_byte(self : UnsignedTransaction) -> Byte? {
  match self {
    Eip1559(_) => Some(0x02)
    Legacy(_) => None
  }
}

///|
/// The fields that describe the transaction itself, in the order the
/// transaction's own EIP fixes. Order is the whole of what says which field is
/// which — RLP carries no names — so this list is the format.
///
/// What follows them differs between the digest and the broadcast bytes, which
/// is `signing_fields` and `signed_fields`.
fn UnsignedTransaction::fields(self : UnsignedTransaction) -> Array[@rlp.Item] {
  match self {
    Eip1559(
      chain_id~,
      nonce~,
      max_priority_fee_per_gas~,
      max_fee_per_gas~,
      gas~,
      to~,
      value~,
      data~
    ) =>
      [
        @rlp.Item::of_uint64(chain_id.to_uint64()),
        @rlp.Item::of_uint64(nonce.to_uint64()),
        @rlp.Item::of_bigint(max_priority_fee_per_gas.to_bigint()),
        @rlp.Item::of_bigint(max_fee_per_gas.to_bigint()),
        @rlp.Item::of_uint64(gas.to_uint64()),
        recipient(to),
        @rlp.Item::of_bigint(value.to_bigint()),
        Bytes(data.to_bytes()),
        // The access list, always empty. See the type.
        List([]),
      ]
    Legacy(nonce~, gas_price~, gas~, to~, value~, data~, ..) =>
      [
        @rlp.Item::of_uint64(nonce.to_uint64()),
        @rlp.Item::of_bigint(gas_price.to_bigint()),
        @rlp.Item::of_uint64(gas.to_uint64()),
        recipient(to),
        @rlp.Item::of_bigint(value.to_bigint()),
        Bytes(data.to_bytes()),
      ]
  }
}

///|
/// The fields the signature commits to.
///
/// A typed transaction signs its fields as they are: the chain id is one of
/// them. A legacy transaction has nowhere to put the chain id, so EIP-155
/// signs `[chain_id, 0, 0]` in place of the `[v, r, s]` a signed transaction
/// would end with — the same nine slots, filled in differently.
fn UnsignedTransaction::signing_fields(
  self : UnsignedTransaction,
) -> Array[@rlp.Item] {
  let fields = self.fields()
  if self is Legacy(chain_id~, ..) {
    fields.push(@rlp.Item::of_uint64(chain_id.to_uint64()))
    fields.push(@rlp.Item::of_uint64(0))
    fields.push(@rlp.Item::of_uint64(0))
  }
  fields
}

///|
/// The fields with the signature on the end.
///
/// A typed transaction carries the parity bit itself. A legacy one carries
/// EIP-155's `v`, which is the parity with the chain id folded in — the only
/// place a legacy transaction says which chain it is for.
fn UnsignedTransaction::signed_fields(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Array[@rlp.Item] {
  let v = match self {
    Eip1559(_) => y_parity.to_uint64()
    Legacy(chain_id~, ..) =>
      y_parity.to_uint64() + chain_id.to_uint64() * 2 + 35
  }
  let fields = self.fields()
  fields.push(@rlp.Item::of_uint64(v))
  fields.push(@rlp.Item::of_bigint(@bigint.BigInt::from_octets(r[:])))
  fields.push(@rlp.Item::of_bigint(@bigint.BigInt::from_octets(s[:])))
  fields
}

///|
/// No recipient is the empty string, not a run of zero bytes: a transaction to
/// the zero address is a different transaction from a contract creation.
fn recipient(to : Address?) -> @rlp.Item {
  match to {
    Some(to) => Bytes(@codec.bytes_of_digits(to.digits()))
    None => Bytes(b"")
  }
}

///|
/// The same transaction as a request to hand a wallet.
///
/// A wallet holding the key fills in nothing here, but it signs and broadcasts
/// in one step, so it has to be asked in the shape that call takes. `from` is
/// the one thing this side does not know.
pub fn UnsignedTransaction::to_request(
  self : UnsignedTransaction,
  from~ : Address,
) -> TransactionRequest {
  match self {
    Eip1559(
      nonce~,
      max_priority_fee_per_gas~,
      max_fee_per_gas~,
      gas~,
      to~,
      value~,
      data~,
      ..
    ) =>
      TransactionRequest::new(
        from,
        to?,
        value~,
        data~,
        gas~,
        nonce~,
        fee=Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~),
      )
    Legacy(nonce~, gas_price~, gas~, to~, value~, data~, ..) =>
      TransactionRequest::new(
        from,
        to?,
        value~,
        data~,
        gas~,
        nonce~,
        fee=Legacy(gas_price~),
      )
  }
}

///|
/// What to sign: `keccak256(type_byte || rlp(fields))`.
///
/// The type byte is outside the RLP, which is what EIP-2718 introduced — an
/// envelope, so that a new transaction format needs a new byte rather than a
/// new way to tell lists apart.
pub fn UnsignedTransaction::signing_digest(self : UnsignedTransaction) -> Bytes {
  @keccak.keccak256(envelope(self.type_byte(), self.signing_fields()))
}

///|
/// The EIP-2718 envelope: the type byte, then the RLP of the fields. Both the
/// digest and the broadcast bytes are this, over different field lists, so the
/// rule that the byte sits *outside* the RLP lives in one place.
fn envelope(type_byte : Byte?, fields : Array[@rlp.Item]) -> Bytes {
  let rlp = @rlp.encode(List(fields))
  match type_byte {
    Some(byte) => Bytes::make(1, byte) + rlp
    None => rlp
  }
}

///|
/// The transaction as it goes to `eth_sendRawTransaction`: the same fields
/// again with the signature appended, under the same type byte.
///
/// Takes the signature in parts, so this package stays independent of the curve
/// that produced it. Raises unless `y_parity` is 0 or 1 — a recovery id of 2 or
/// 3 says `r` wrapped past the group order, which no transaction can carry.
pub fn UnsignedTransaction::encode_signed(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Hex raise CodecError {
  guard y_parity == 0 || y_parity == 1 else {
    raise InvalidValue("y parity must be 0 or 1: \{y_parity}")
  }
  guard r.length() == 32 && s.length() == 32 else {
    raise InvalidValue("r and s must be 32 bytes each")
  }
  Hex::from_bytes(
    envelope(self.type_byte(), self.signed_fields(r~, s~, y_parity~)),
  )
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
