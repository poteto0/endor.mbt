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
/// Implemented here by `@raw.RawAccount`, which holds a private key. A
/// wallet-backed account is a different shape — every method is a round trip
/// to the extension, so it is asynchronous and does not fit this trait; that
/// is `@provider`'s side of the SDK.
pub(open) trait Account {
  /// The whole signed transaction, as `eth_sendRawTransaction` takes it.
  fn sign_transaction(self : Self, tx : @types.UnsignedTransaction) -> @types.Hex raise AccountError

  /// A `personal_sign` signature over the EIP-191 prefixed message.
  fn sign_message(self : Self, message : @types.Hex) -> @types.Hex raise AccountError

  /// An `eth_signTypedData_v4` signature over the EIP-712 document.
  fn sign_typed_data(self : Self, typed_data : @eip712.TypedData) -> @types.Hex raise AccountError

  /// The address these signatures will recover to.
  fn address(self : Self) -> @types.Address raise AccountError

  /// Which kind of account this is, for a caller holding several.
  fn account_type(self : Self) -> String
}
