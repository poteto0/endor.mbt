///|
/// The offset `v` carries for a signature that is not a typed transaction's.
/// `personal_sign` and `eth_signTypedData_v4` both answer with `27` or `28`;
/// a typed transaction carries the bare parity bit instead, because its chain
/// id is already one of the signed fields.
///
/// The 27 predates EIP-155 — that is the one that made `v` carry a chain id,
/// and it applies to legacy transactions rather than to these.
const V_OFFSET = 27

///|
/// An account that signs with a private key this process holds.
///
/// It signs locally and reaches no node and no wallet, which is what makes it
/// the account for a script, a backend, or a test. It is also the account that
/// can lose the key: anything that can read this value can sign anything at
/// all with it, so a browser is the wrong place for one — there the wallet
/// holds the key and `@provider` asks it to sign.
///
/// The address is derived in the constructor, from the key itself. It is not
/// something a caller passes in, so an account cannot claim an address its key
/// does not sign for.
pub struct LocalAccount {
  priv priv_key : @secp256k1.PrivateKey
  priv address : @types.Address
}

///|
/// Read a private key and derive the account it is.
///
/// ```
/// let account = @local.LocalAccount::new(
///   @types.Hex::from_string(
///     "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
///   ),
/// )
/// inspect(
///   account.address().to_checksum_string(),
///   content="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
/// )
/// ```
pub fn LocalAccount::new(
  priv_key_hex : @types.Hex,
) -> LocalAccount raise @account.AccountError {
  // Both ways a scalar can fail — the wrong width, and a value outside
  // `[1, N)` — are the same thing to a caller who handed over a bad key.
  let priv_key = @secp256k1.PrivateKey::from_bytes(priv_key_hex.to_bytes()) catch {
    e => raise @account.AccountError::InvalidPrivateKey(e.to_string())
  }
  // Cannot fail: the key derives its own point, and the address is the tail of
  // a hash of it. Mapped anyway, because a constructor that swallows an error
  // is worse than one that reports an impossible one.
  let address = @types.Address::from_public_key(priv_key.public_key()) catch {
    e => raise @account.AccountError::InvalidPrivateKey(e.to_string())
  }
  LocalAccount::{ priv_key, address }
}

///|
/// Sign a digest and render the 65 bytes a verifier is handed, with the `v`
/// offset a signature outside a typed transaction carries.
fn LocalAccount::sign_offset(
  self : LocalAccount,
  digest : Bytes,
) -> @types.Hex raise @account.AccountError {
  let signature = self.priv_key.sign(digest) catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
  @types.Hex::from_bytes(signature.to_bytes(v_offset=V_OFFSET))
}

///|
/// The signed transaction, ready for `eth_sendRawTransaction`.
///
/// ```
/// let account = @local.LocalAccount::new(
///   @types.Hex::from_string(
///     "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
///   ),
/// )
/// let tx = @types.UnsignedTransaction::new(
///   chain_id=@types.ChainId::mainnet(),
///   nonce=@types.Quantity::new(0),
///   max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
///   max_fee_per_gas=@types.Wei::from_gwei("20"),
///   gas=@types.Quantity::new(21000),
///   to=@types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
///   value=@types.Wei::from_ether("1"),
/// )
/// assert_eq(account.sign_transaction(tx).byte_length(), 116)
/// ```
pub impl @account.Account for LocalAccount with fn sign_transaction(
  self : LocalAccount,
  tx : @types.UnsignedTransaction,
) -> @types.Hex raise @account.AccountError {
  let signature = self.priv_key.sign(tx.signing_digest()) catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
  tx.encode_signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  ) catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
}

///|
/// A `personal_sign` signature: the message under the EIP-191 prefix, which is
/// what stops a signer from being talked into signing a transaction that was
/// handed over as text.
pub impl @account.Account for LocalAccount with fn sign_message(
  self : LocalAccount,
  message : @types.Hex,
) -> @types.Hex raise @account.AccountError {
  self.sign_offset(@eip191.hash_bytes(message.to_bytes()).to_bytes())
}

///|
/// An `eth_signTypedData_v4` signature over the EIP-712 document.
pub impl @account.Account for LocalAccount with fn sign_typed_data(
  self : LocalAccount,
  typed_data : @eip712.TypedData,
) -> @types.Hex raise @account.AccountError {
  let digest = typed_data.digest() catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
  self.sign_offset(digest.to_bytes())
}

///|
/// The address this account's signatures recover to, derived from the key.
pub impl @account.Account for LocalAccount with fn address(self : LocalAccount) -> @types.Address {
  self.address
}

///|
pub impl @account.Account for LocalAccount with fn account_type(
  _self : LocalAccount,
) -> String {
  @account.LOCAL
}
