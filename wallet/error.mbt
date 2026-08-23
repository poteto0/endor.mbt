///|
/// What can go wrong driving a write through a client.
///
/// A client is a transport and an account joined, and the error that happened is
/// carried whole rather than flattened into a string: a caller can still match
/// on the `ProviderError` inside. `Incomplete` is the client's own — a field it
/// was asked to fill in and could not.
pub(all) suberror WalletError {
  /// The transport, or the node behind it, said no.
  Provider(@provider.ProviderError)
  /// The account could not sign.
  Account(@account.AccountError)
  /// A transaction field was left out and could not be worked out from the
  /// node either.
  Incomplete(String)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for WalletError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One line to put in front of a person. The two wrapped errors already answer
/// this question, so it is theirs to answer.
pub fn WalletError::message(self : WalletError) -> String {
  match self {
    Provider(e) => e.message()
    Account(e) => e.message()
    Incomplete(_) => "That transaction is missing something."
  }
}

///|
/// Worth a second attempt only when the thing that failed says so — a node
/// that was busy, never a signature that was declined.
pub fn WalletError::is_retryable(self : WalletError) -> Bool {
  match self {
    Provider(e) => e.is_retryable()
    Account(e) => e.is_retryable()
    Incomplete(_) => false
  }
}
