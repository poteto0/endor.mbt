///|
/// What can go wrong asking an account to act.
///
/// `InvalidPrivateKey` is material that is not a key, `SigningFailed` a key that
/// could not be used on this input, and `InvalidAccountType` / `NotSupported`
/// are about the account itself. `pub(all)`, so an `Account` implemented
/// outside this package can say the same things.
pub(all) suberror AccountError {
  /// The account cannot do this at all — a hardware wallet asked for a raw
  /// key, a read-only account asked to sign.
  NotSupported(String)
  /// The account was described as a kind that does not exist.
  InvalidAccountType(String)
  /// The material handed over is not a private key: the wrong length, or a
  /// scalar the curve has no point for.
  InvalidPrivateKey(String)
  /// The key is fine and the signature still could not be produced — a digest
  /// of the wrong width, a document that does not encode.
  SigningFailed(String)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for AccountError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One line to put in front of a person, with no variant name in it.
pub fn AccountError::message(self : AccountError) -> String {
  match self {
    NotSupported(_) => "This account cannot do that."
    InvalidAccountType(_) => "That is not a kind of account."
    InvalidPrivateKey(_) => "That is not a valid private key."
    SigningFailed(_) => "That could not be signed."
  }
}

///|
/// Never: none of these change on a second attempt. A key that is not a key
/// stays one, and an account that cannot sign will not start.
pub fn AccountError::is_retryable(_self : AccountError) -> Bool {
  false
}
