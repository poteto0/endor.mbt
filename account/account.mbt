///|
/// Something that can sign on behalf of one address.
///
/// The signing methods are separate because what gets hashed differs for each:
/// RLP under a type byte, EIP-191 prefixed, EIP-712 structured, RLP under a
/// magic byte. A method that signed "some bytes" would be a signing oracle.
pub(open) trait Account {
  /// The whole signed transaction, as `eth_sendRawTransaction` takes it.
  async fn sign_transaction(self : Self, tx : @types.UnsignedTransaction) -> @types.Hex raise AccountError

  /// A `personal_sign` signature over the EIP-191 prefixed message.
  async fn sign_message(self : Self, message : @types.Hex) -> @types.Hex raise AccountError

  /// An `eth_signTypedData_v4` signature over the EIP-712 document.
  async fn sign_typed_data(self : Self, typed_data : @eip712.TypedData) -> @types.Hex raise AccountError

  /// An EIP-7702 authorization with this account's signature on it. Not a
  /// `Hex`: a transaction carries the six-element tuple, not the 65 bytes.
  async fn sign_authorization(self : Self, authorization : @types.Authorization) -> @types.SignedAuthorization raise AccountError

  /// The address these signatures will recover to.
  fn address(self : Self) -> @types.Address raise AccountError

  /// Which kind of account this is, for a caller holding several.
  fn account_type(self : Self) -> String
}

///|
/// What `account_type` answers for an account that holds its own key and signs
/// without leaving the process.
pub const LOCAL = "local"

///|
/// What `account_type` answers for an account whose key is behind a JSON-RPC
/// endpoint — a browser wallet, or a node with the account unlocked.
///
/// Worth a name because one thing turns on it: such an account cannot hand back
/// a signed transaction. Wallets sign and broadcast in one step, and most do
/// not implement `eth_signTransaction` at all.
pub const JSON_RPC = "json-rpc"
