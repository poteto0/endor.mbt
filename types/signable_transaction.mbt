///|
/// A transaction whose RLP fields are built already, asked for a digest or for
/// bytes to broadcast as many times as the caller likes.
///
/// Building the fields decodes the calldata out of hex, the recipient, and
/// every storage key the access list declares, so a caller that asks more than
/// one question takes one of these rather than asking the transaction itself.
pub struct SignableTransaction {
  priv type_byte : Byte?
  priv fields : Array[@rlp.Item]
  /// A legacy transaction's chain id, and nothing else's: it has no field to
  /// carry the chain id, so EIP-155 signs it in the three slots the signature
  /// later fills, and folds it into `v`.
  priv legacy_chain_id : ChainId?
} derive(Eq, Debug)

///|
/// The fields built once, to sign over and then to broadcast.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
///   ),
/// )
/// let signable = @types.UnsignedTransaction::new(
///   chain_id=@types.ChainId::mainnet(),
///   nonce=@types.Quantity::new(0),
///   max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
///   max_fee_per_gas=@types.Wei::from_gwei("20"),
///   gas=@types.Quantity::new(21000),
///   to=@types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
///   value=@types.Wei::from_ether("1"),
/// ).signable()
/// let signature = key.sign(signable.signing_digest())
/// let raw = signable.encode_signed(
///   r=signature.r(),
///   s=signature.s(),
///   y_parity=signature.recovery_id(),
/// )
/// assert_eq(raw.byte_length(), 116)
/// ```
pub fn UnsignedTransaction::signable(
  self : UnsignedTransaction,
) -> SignableTransaction {
  let legacy_chain_id = match self {
    Legacy(chain_id~, ..) => Some(chain_id)
    Eip1559(_) | Eip2930(_) | Eip7702(_) => None
  }
  SignableTransaction::{
    type_byte: self.type_byte(),
    fields: self.fields(),
    legacy_chain_id,
  }
}

///|
/// What to sign: `keccak256(type_byte || rlp(fields))`.
///
/// The type byte is outside the RLP, which is what EIP-2718 introduced — an
/// envelope, so that a new transaction format needs a new byte rather than a
/// new way to tell lists apart.
pub fn SignableTransaction::signing_digest(self : SignableTransaction) -> Bytes {
  // only the legacy form appends, so only the legacy form needs its own array
  let fields = match self.legacy_chain_id {
    Some(chain_id) => {
      let fields = self.fields.copy()
      fields.push(@rlp.Item::of_uint64(chain_id.to_uint64()))
      fields.push(@rlp.Item::of_uint64(0))
      fields.push(@rlp.Item::of_uint64(0))
      fields
    }
    None => self.fields
  }
  @keccak.keccak256(envelope(self.type_byte, fields))
}

///|
/// The broadcast bytes themselves, so that `hash` does not go through the hex
/// string `encode_signed` builds only to take it apart again.
///
/// A typed transaction carries the parity bit itself; a legacy one carries
/// EIP-155's `v`.
fn SignableTransaction::signed_bytes(
  self : SignableTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Bytes raise CodecError {
  check_signature(r~, s~, y_parity~)
  let v = match self.legacy_chain_id {
    Some(chain_id) => y_parity.to_uint64() + chain_id.to_uint64() * 2 + 35
    None => y_parity.to_uint64()
  }
  let fields = self.fields.copy()
  push_signature(fields, v~, r~, s~)
  envelope(self.type_byte, fields)
}

///|
/// The transaction as it goes to `eth_sendRawTransaction`: the same fields
/// again with the signature appended, under the same type byte.
///
/// Takes the signature in parts, so this package stays independent of the curve
/// that produced it. Raises unless `y_parity` is 0 or 1 — a recovery id of 2 or
/// 3 says `r` wrapped past the group order, which no transaction can carry.
pub fn SignableTransaction::encode_signed(
  self : SignableTransaction,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> Hex raise CodecError {
  Hex::from_bytes(self.signed_bytes(r~, s~, y_parity~))
}

///|
/// The hash the transaction will be known by once it is broadcast: the
/// Keccak-256 of exactly the bytes `encode_signed` produces.
pub fn SignableTransaction::hash(
  self : SignableTransaction,
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
