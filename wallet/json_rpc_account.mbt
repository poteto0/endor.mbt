///|
/// An account whose key is behind a JSON-RPC endpoint: the browser wallet the
/// page is talking to, or a node with the account unlocked.
///
/// It holds no key. Every signature is a request over the same transport the
/// reads go over, and — for a browser wallet — a prompt the user has to
/// approve, which is why the `Account` methods are asynchronous.
///
/// The address is given rather than derived: this side cannot compute an
/// address it has no key for. Pass one the endpoint actually controls
/// (`@provider.require_account`), or the wallet will refuse with
/// `Unauthorized`.
///
/// It lives here and not in `account/` because it needs a `Provider`, and
/// `account` sits below `provider` — an account that reaches a transport is a
/// client-layer thing.
pub struct JsonRpcAccount[P] {
  priv provider : P
  priv address : @types.Address
}

///|
/// Name the account behind `provider` that signatures are to be asked of.
///
/// ```
/// async fn[P : @provider.Provider] whoever_is_connected(
///   p : P,
/// ) -> @wallet.JsonRpcAccount[P] raise @provider.ProviderError {
///   @wallet.JsonRpcAccount::new(p, @provider.require_account(p))
/// }
/// ```
pub fn[P] JsonRpcAccount::new(
  provider : P,
  address : @types.Address,
) -> JsonRpcAccount[P] {
  { provider, address }
}

///|
/// Never: a wallet signs and broadcasts in one step, and `eth_signTransaction`
/// — the call that would hand the signed bytes back instead — is not something
/// MetaMask and most other wallets implement.
///
/// `WalletClient::send_transaction` is the way to send one with this kind of
/// account; it asks the wallet to do both at once.
pub impl[P : @provider.Provider] @account.Account for JsonRpcAccount[P] with fn sign_transaction(
  _self : JsonRpcAccount[P],
  _tx : @types.UnsignedTransaction,
) -> @types.Hex raise @account.AccountError {
  raise @account.AccountError::NotSupported(
    "a wallet signs and sends in one step; use WalletClient::send_transaction",
  )
}

///|
/// `personal_sign` over the wire, with the wallet applying the EIP-191 prefix
/// itself.
pub impl[P : @provider.Provider] @account.Account for JsonRpcAccount[P] with fn sign_message(
  self : JsonRpcAccount[P],
  message : @types.Hex,
) -> @types.Hex raise @account.AccountError {
  @provider.sign_message_bytes(self.provider, self.address, message) catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
}

///|
/// `eth_signTypedData_v4` over the wire.
pub impl[P : @provider.Provider] @account.Account for JsonRpcAccount[P] with fn sign_typed_data(
  self : JsonRpcAccount[P],
  typed_data : @eip712.TypedData,
) -> @types.Hex raise @account.AccountError {
  @provider.sign_typed_data(self.provider, self.address, typed_data) catch {
    e => raise @account.AccountError::SigningFailed(e.to_string())
  }
}

///|
pub impl[P : @provider.Provider] @account.Account for JsonRpcAccount[P] with fn address(
  self : JsonRpcAccount[P],
) -> @types.Address {
  self.address
}

///|
pub impl[P : @provider.Provider] @account.Account for JsonRpcAccount[P] with fn account_type(
  _self : JsonRpcAccount[P],
) -> String {
  @account.JSON_RPC
}
