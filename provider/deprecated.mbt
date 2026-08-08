///|
/// Everything the SDK's own failures used to be spelled as, before they had
/// variants of their own (#113).
///
/// `internal` flattened nineteen different failures — a node that could not be
/// reached, a response that would not parse, a URL with a typo — into one
/// `Rpc(code=-32603, …)`, which claimed the node had had an internal error even
/// when no request had left the process, and left telling them apart to a match
/// on the message string. Each of them now has a variant: `Transport`,
/// `HttpStatus`, `MalformedResponse`, `Decode`, `Config`.
#deprecated("raise the variant that says what happened: Transport, HttpStatus, MalformedResponse, Decode or Config")
pub fn ProviderError::internal(message : String) -> ProviderError {
  Rpc(code=-32603, message~)
}
