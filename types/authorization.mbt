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
/// Chain id `0` raises: it does not name a chain, it means *every* chain, and
/// that is `any_chain`'s to say. So the every-chain authorization cannot be
/// arrived at by passing a variable that happened to be zero.
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
) -> Authorization raise CodecError {
  guard chain_id.to_uint64() != 0 else {
    raise InvalidValue(
      "chain id 0 authorizes every chain: say Authorization::any_chain",
    )
  }
  Authorization::{ chain_id, address, nonce }
}

///|
/// Authorize `address` on every chain at once, which is what chain id `0`
/// means.
///
/// The only way to spell chain id `0`, and it takes no chain id at all: the
/// same signature is replayable on every chain the authority exists on, at
/// that nonce, so it is asked for by name or not at all.
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

///|
/// The chain the authorization is for. `0` is the every-chain form.
pub fn Authorization::chain_id(self : Authorization) -> ChainId {
  self.chain_id
}

///|
/// The address whose code the authority delegates to. The zero address is a
/// revocation.
pub fn Authorization::address(self : Authorization) -> Address {
  self.address
}

///|
/// The authority's own account nonce — not the carrying transaction's.
pub fn Authorization::nonce(self : Authorization) -> Quantity {
  self.nonce
}

///|
/// The EOA that signed this authorization: ecrecover over `signing_digest`.
///
/// This is the account that ends up delegating, and nothing in the
/// authorization names it — it is only reachable through the signature. A
/// transaction carrying an authorization whose nonce was wrong is valid and
/// mines; it is the delegation that silently does not happen. So the way to
/// check one before broadcasting is to recover the authority and compare it
/// with the account whose nonce was used.
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
/// inspect(
///   signed.authority().to_string(),
///   content="0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
/// )
/// ```
pub fn SignedAuthorization::authority(
  self : SignedAuthorization,
) -> Address raise @secp256k1.CurveError {
  Address::recover(
    self.authorization.signing_digest(),
    @secp256k1.Signature::from_bytes(
      self.r + self.s + Bytes::make(1, self.y_parity.to_byte()),
    ),
  )
}

///|
/// Encode as the JSON object an `authorizationList` is made of — what
/// `eth_sendTransaction` takes and what a node answers with on a type-`0x04`
/// transaction and its receipt.
///
/// `r` and `s` go out as full words. A node may answer with them trimmed,
/// which `from_json` reads back.
pub fn SignedAuthorization::to_json(self : SignedAuthorization) -> Json {
  Json::object({
    "chainId": self.authorization.chain_id.to_json(),
    "address": self.authorization.address.to_json(),
    "nonce": self.authorization.nonce.to_json(),
    "yParity": Quantity::new(self.y_parity.to_uint64()).to_json(),
    "r": Hex::from_bytes(self.r).to_json(),
    "s": Hex::from_bytes(self.s).to_json(),
  })
}

///|
/// Decode one entry of an `authorizationList`.
///
/// Chain id `0` is read as what it is. On the way out it is `any_chain`'s
/// alone, so that it cannot be arrived at by accident; on the way in it is
/// something a node said, and refusing it would leave an authorization that
/// exists unreadable.
///
/// ```
/// let signed = @types.SignedAuthorization::from_json({
///   "chainId": "0x1",
///   "address": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
///   "nonce": "0x0",
///   "yParity": "0x1",
///   "r": "0x1",
///   "s": "0x2",
/// })
/// assert_eq(signed.authorization().nonce(), @types.Quantity::new(0))
/// ```
pub fn SignedAuthorization::from_json(
  j : Json,
) -> SignedAuthorization raise CodecError {
  let what = "authorization"
  let fields = json_object(j, what~)
  let authorization = Authorization::{
    chain_id: ChainId::from_json(required_field(fields, "chainId", what~)),
    address: Address::from_json(required_field(fields, "address", what~)),
    nonce: Quantity::from_json(required_field(fields, "nonce", what~)),
  }
  let y_parity = quantity_field(fields, "yParity", what~)
  guard y_parity <= 1 else {
    raise InvalidValue("y parity must be 0 or 1: \{y_parity}")
  }
  SignedAuthorization::{
    authorization,
    y_parity: y_parity.to_int(),
    r: signature_word(required_field(fields, "r", what~), name="r"),
    s: signature_word(required_field(fields, "s", what~), name="s"),
  }
}
