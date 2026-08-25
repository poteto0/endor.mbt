///|
/// An EIP-7702 authorization: an EOA's word that it runs the code at `address`
/// until it says otherwise.
///
/// Signed on its own, under a magic byte of its own, and only then carried by a
/// transaction — so the account that delegates and the account that pays for
/// the transaction need not be the same one.
pub struct Authorization {
  priv chain_id : ChainId
  priv address : Address
  priv nonce : Quantity
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, as the rest of `types`
/// does.
pub impl Show for Authorization with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Authorize `address` on one chain.
///
/// `nonce` is the *authority's* own account nonce, not the carrying
/// transaction's. The zero address is a revocation.
///
/// ```
/// let auth = @types.Authorization::new(
///   chain_id=@types.ChainId::mainnet(),
///   address=@types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
///   nonce=@types.Quantity::new(0),
/// )
/// assert_eq(auth.signing_digest().length(), 32)
/// ```
pub fn Authorization::new(
  chain_id~ : ChainId,
  address~ : Address,
  nonce~ : Quantity,
) -> Authorization {
  Authorization::{ chain_id, address, nonce }
}

///|
/// Authorize `address` on every chain at once, which is what chain id `0`
/// means.
///
/// It has its own name because it is the dangerous one: the same signature is
/// replayable on any chain the authority exists on, at that nonce.
pub fn Authorization::any_chain(
  address~ : Address,
  nonce~ : Quantity,
) -> Authorization {
  Authorization::{ chain_id: ChainId::new(0), address, nonce }
}

///|
/// What the authority signs: `keccak256(0x05 || rlp([chain_id, address,
/// nonce]))`.
///
/// The magic byte is not a transaction type — it is what keeps an authorization
/// from being read as one.
pub fn Authorization::signing_digest(self : Authorization) -> Bytes {
  @keccak.keccak256(envelope(Some(0x05), self.fields()))
}

///|
fn Authorization::fields(self : Authorization) -> Array[@rlp.Item] {
  [
    @rlp.Item::of_uint64(self.chain_id.to_uint64()),
    address_item(self.address),
    @rlp.Item::of_uint64(self.nonce.to_uint64()),
  ]
}

///|
/// An authorization with the authority's signature on it — the form a
/// transaction carries.
pub struct SignedAuthorization {
  priv authorization : Authorization
  priv y_parity : Int
  priv r : Bytes
  priv s : Bytes
} derive(Eq, Debug)

///|
pub impl Show for SignedAuthorization with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Attach a signature over `signing_digest`. Raises on a signature no
/// authorization can carry, on the same terms as
/// `UnsignedTransaction::encode_signed`.
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
///   nonce=@types.Quantity::new(0),
/// )
/// let signature = key.sign(auth.signing_digest())
/// let signed = auth.signed(
///   r=signature.r(),
///   s=signature.s(),
///   y_parity=signature.recovery_id(),
/// )
/// assert_eq(signed.authorization(), auth)
/// ```
pub fn Authorization::signed(
  self : Authorization,
  r~ : Bytes,
  s~ : Bytes,
  y_parity~ : Int,
) -> SignedAuthorization raise CodecError {
  check_signature(r~, s~, y_parity~)
  SignedAuthorization::{ authorization: self, y_parity, r, s }
}

///|
/// The authorization the signature is over.
pub fn SignedAuthorization::authorization(
  self : SignedAuthorization,
) -> Authorization {
  self.authorization
}

///|
/// The six-element tuple a transaction's `authorization_list` is made of:
/// the three signed fields, then the signature.
fn SignedAuthorization::to_rlp(self : SignedAuthorization) -> @rlp.Item {
  let items = self.authorization.fields()
  // An authorization signs no chain id into its parity: `v` is the bit itself.
  push_signature(items, v=self.y_parity.to_uint64(), r=self.r, s=self.s)
  List(items)
}
