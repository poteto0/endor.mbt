///|
/// A transaction with everything filled in, ready to be signed — the other half
/// of `TransactionRequest`. Nothing may be left open, because every field is
/// part of what the signature commits to.
///
/// One variant per EIP-2718 transaction type, plus the legacy form that
/// predates the envelope. The access list is always empty: it is part of the
/// signed bytes, but nothing here builds one.
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
  /// The pre-EIP-2718 form, for a chain with no EIP-1559 market.
  Legacy(
    chain_id~ : ChainId,
    nonce~ : Quantity,
    gas_price~ : Wei,
    gas~ : Quantity,
    to~ : Address?,
    value~ : Wei,
    data~ : Hex
  )
  /// EIP-7702. `to` is not optional: a delegating transaction creates nothing.
  Eip7702(
    chain_id~ : ChainId,
    nonce~ : Quantity,
    max_priority_fee_per_gas~ : Wei,
    max_fee_per_gas~ : Wei,
    gas~ : Quantity,
    to~ : Address,
    value~ : Wei,
    data~ : Hex,
    authorization_list~ : Array[SignedAuthorization]
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
/// Build a legacy transaction, for a chain that never forked to London.
/// Everything but the price is `new`'s.
///
/// The signature is always EIP-155's: a pre-155 transaction, `v` of 27 or 28
/// and bound to no chain, is one every chain would replay.
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
/// Build an EIP-7702 transaction: the 1559 fields, plus the authorizations it
/// puts on chain.
///
/// `to` is required by the type — a delegating transaction creates nothing —
/// and an empty `authorization_list` raises. The list is copied in.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
///   ),
/// )
/// let auth = @types.Authorization::new(
///   chain_id=@types.ChainId::mainnet(),
///   address=@types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
///   nonce=@types.Quantity::new(1),
/// )
/// let signature = key.sign(auth.signing_digest())
/// let tx = @types.UnsignedTransaction::eip7702(
///   chain_id=@types.ChainId::mainnet(),
///   nonce=@types.Quantity::new(0),
///   max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
///   max_fee_per_gas=@types.Wei::from_gwei("20"),
///   gas=@types.Quantity::new(100000),
///   to=@types.Address::from_string("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
///   authorization_list=[
///     auth.signed(
///       r=signature.r(),
///       s=signature.s(),
///       y_parity=signature.recovery_id(),
///     ),
///   ],
/// )
/// assert_eq(tx.signing_digest().length(), 32)
/// ```
pub fn UnsignedTransaction::eip7702(
  chain_id~ : ChainId,
  nonce~ : Quantity,
  max_priority_fee_per_gas~ : Wei,
  max_fee_per_gas~ : Wei,
  gas~ : Quantity,
  to~ : Address,
  authorization_list~ : Array[SignedAuthorization],
  value? : Wei = Wei::zero(),
  data? : Hex = Hex::from_bytes(b""),
) -> UnsignedTransaction raise CodecError {
  guard authorization_list.length() > 0 else {
    raise InvalidValue("a 7702 transaction needs at least one authorization")
  }
  Eip7702(
    chain_id~,
    nonce~,
    max_priority_fee_per_gas~,
    max_fee_per_gas~,
    gas~,
    to~,
    value~,
    data~,
    authorization_list=authorization_list.copy(),
  )
}

///|
/// The type byte EIP-2718 introduces the transaction by. A legacy transaction
/// has none, which is what `None` is for.
fn UnsignedTransaction::type_byte(self : UnsignedTransaction) -> Byte? {
  match self {
    Eip1559(_) => Some(0x02)
    Eip7702(_) => Some(0x04)
    Legacy(_) => None
  }
}

///|
/// The fields that describe the transaction itself, in the order the
/// transaction's own EIP fixes. Order is the whole of what says which field is
/// which — RLP carries no names — so this list is the format.
///
/// What follows them is `signing_fields`' and `signed_fields`' to say.
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
      priced_fields(
        chain_id~,
        nonce~,
        max_priority_fee_per_gas~,
        max_fee_per_gas~,
        gas~,
        to=recipient(to),
        value~,
        data~,
      )
    Eip7702(
      chain_id~,
      nonce~,
      max_priority_fee_per_gas~,
      max_fee_per_gas~,
      gas~,
      to~,
      value~,
      data~,
      authorization_list~
    ) => {
      let fields = priced_fields(
        chain_id~,
        nonce~,
        max_priority_fee_per_gas~,
        max_fee_per_gas~,
        gas~,
        to=address_item(to),
        value~,
        data~,
      )
      fields.push(List(authorization_list.map(SignedAuthorization::to_rlp)))
      fields
    }
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
/// A typed transaction signs its fields as they are. A legacy one has no field
/// for the chain id, so EIP-155 signs `[chain_id, 0, 0]` in the three slots
/// `signed_fields` fills with the signature.
fn UnsignedTransaction::signing_fields(
  self : UnsignedTransaction,
) -> Array[@rlp.Item] {
  let fields = self.fields()
  match self {
    Eip1559(_) | Eip7702(_) => ()
    Legacy(chain_id~, ..) => {
      fields.push(@rlp.Item::of_uint64(chain_id.to_uint64()))
      fields.push(@rlp.Item::of_uint64(0))
      fields.push(@rlp.Item::of_uint64(0))
    }
  }
  fields
}

///|
/// The fields with the signature on the end.
///
/// A typed transaction carries the parity bit itself. A legacy one carries
/// EIP-155's `v`, the parity with the chain id folded in — the only place it
/// says which chain it is for.
fn UnsignedTransaction::signed_fields(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Array[@rlp.Item] {
  let v = match self {
    Eip1559(_) | Eip7702(_) => y_parity.to_uint64()
    Legacy(chain_id~, ..) =>
      y_parity.to_uint64() + chain_id.to_uint64() * 2 + 35
  }
  let fields = self.fields()
  push_signature(fields, v~, r~, s~)
  fields
}

///|
/// The nine fields EIP-1559 fixed and every type since has begun with. A later
/// type adds to the end of this list and changes nothing in it.
fn priced_fields(
  chain_id~ : ChainId,
  nonce~ : Quantity,
  max_priority_fee_per_gas~ : Wei,
  max_fee_per_gas~ : Wei,
  gas~ : Quantity,
  to~ : @rlp.Item,
  value~ : Wei,
  data~ : Hex,
) -> Array[@rlp.Item] {
  [
    @rlp.Item::of_uint64(chain_id.to_uint64()),
    @rlp.Item::of_uint64(nonce.to_uint64()),
    @rlp.Item::of_bigint(max_priority_fee_per_gas.to_bigint()),
    @rlp.Item::of_bigint(max_fee_per_gas.to_bigint()),
    @rlp.Item::of_uint64(gas.to_uint64()),
    to,
    @rlp.Item::of_bigint(value.to_bigint()),
    Bytes(data.to_bytes()),
    // The access list, always empty. See the type.
    List([]),
  ]
}

///|
/// No recipient is the empty string, not a run of zero bytes: a transaction to
/// the zero address is a different transaction from a contract creation.
fn recipient(to : Address?) -> @rlp.Item {
  match to {
    Some(to) => address_item(to)
    None => Bytes(b"")
  }
}

///|
fn address_item(address : Address) -> @rlp.Item {
  Bytes(@codec.bytes_of_digits(address.digits()))
}

///|
/// The same transaction as a request to hand a wallet.
///
/// A wallet holding the key fills in nothing here, but it signs and broadcasts
/// in one step, so it has to be asked in the shape that call takes. `from` is
/// the one thing this side does not know.
///
/// `None` for a transaction with no request form: `eth_sendTransaction` carries
/// a 7702 authorization list in a field this type does not have, and sending it
/// without one would send a different transaction.
pub fn UnsignedTransaction::to_request(
  self : UnsignedTransaction,
  from~ : Address,
) -> TransactionRequest? {
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
      Some(
        TransactionRequest::new(
          from,
          to?,
          value~,
          data~,
          gas~,
          nonce~,
          fee=Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~),
        ),
      )
    Legacy(nonce~, gas_price~, gas~, to~, value~, data~, ..) =>
      Some(
        TransactionRequest::new(
          from,
          to?,
          value~,
          data~,
          gas~,
          nonce~,
          fee=Legacy(gas_price~),
        ),
      )
    Eip7702(_) => None
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
/// A byte outside the RLP, then the RLP of the fields — the shape EIP-2718
/// introduced for its type byte and EIP-7702 borrowed for its magic byte. Every
/// digest and every broadcast body here is this, so the rule that the byte sits
/// *outside* the RLP lives in one place.
fn envelope(leading_byte : Byte?, fields : Array[@rlp.Item]) -> Bytes {
  let rlp = @rlp.encode(List(fields))
  match leading_byte {
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
  Hex::from_bytes(self.signed_bytes(r~, s~, y_parity~))
}

///|
/// The broadcast bytes themselves, so that `hash` does not go through the hex
/// string `encode_signed` builds only to take it apart again.
fn UnsignedTransaction::signed_bytes(
  self : UnsignedTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Bytes raise CodecError {
  check_signature(r~, s~, y_parity~)
  envelope(self.type_byte(), self.signed_fields(r~, s~, y_parity~))
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
      @keccak.keccak256(self.signed_bytes(r~, s~, y_parity~)),
    ),
  )
}
