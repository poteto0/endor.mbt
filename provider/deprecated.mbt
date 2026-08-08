///|
/// What the SDK's own failures were spelled as before they had variants of
/// their own. Each of them now says what happened — `Transport`, `HttpStatus`,
/// `MalformedResponse`, `Decode`, `Config` — and `ProviderError`'s own doc says
/// why that is worth a breaking change (#113).
#deprecated("raise the variant that says what happened: Transport, HttpStatus, MalformedResponse, Decode or Config")
pub fn ProviderError::internal(message : String) -> ProviderError {
  Rpc(code=INTERNAL_ERROR, message~)
}
