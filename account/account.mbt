///|
/// Something that can sign on behalf of one address.
///
/// The three signing methods are the three things Ethereum asks a key to sign,
/// and they are separate because what gets hashed differs for each: a
/// transaction is RLP under a type byte, a message is EIP-191 prefixed, a
/// document is EIP-712 structured. A method that took "some bytes" and signed
/// them would be a signing oracle — anyone who could choose the bytes could
/// have a transaction signed by calling it a message.
///
/// `sign_transaction` answers with the whole signed transaction, ready for
/// `eth_sendRawTransaction`, because a transaction signature is of no use
/// apart from the bytes it commits to. The other two answer with the 65-byte
/// signature, which is what a verifier is handed.
///
/// `tx` is an `UnsignedTransaction` and not a `Transaction`: the latter is
/// what a node reports back, with a hash and a block already on it, and there
/// is nothing left to sign about it.
///
/// Signing is `async` because a wallet-backed account signs by asking the
/// extension and waiting for the user; one that holds its own key, like
/// `@local.LocalAccount`, satisfies it without ever awaiting.
///
/// The two accessors are not: an address and a kind are properties an account
/// already knows, whichever sort it is.
pub(open) trait Account {
  /// The whole signed transaction, as `eth_sendRawTransaction` takes it.
  async fn sign_transaction(self : Self, tx : @types.UnsignedTransaction) -> @types.Hex raise AccountError

  /// A `personal_sign` signature over the EIP-191 prefixed message.
  async fn sign_message(self : Self, message : @types.Hex) -> @types.Hex raise AccountError

  /// An `eth_signTypedData_v4` signature over the EIP-712 document.
  async fn sign_typed_data(self : Self, typed_data : @eip712.TypedData) -> @types.Hex raise AccountError

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
/// The distinction is worth a name because one thing turns on it: an account
/// of this kind cannot hand back a signed transaction. Wallets sign and
/// broadcast in one step (`eth_sendTransaction`) and most, MetaMask included,
/// do not implement `eth_signTransaction` at all.
pub const JSON_RPC = "json-rpc"
