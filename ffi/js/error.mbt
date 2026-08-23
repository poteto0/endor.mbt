///|
/// What the FFI boundary itself reports, before anything decides which
/// `ProviderError` it is — that mapping is `provider/error.mbt`'s, where it is
/// testable.
pub(all) suberror JsError {
  /// The `{ok}` / `{err}` envelope `request` promises came back as something
  /// else: not JSON, not an object, or carrying neither member.
  InvalidEnvelope(String)
  /// The wallet rejected the call: its `code` and `message`, and whatever it
  /// hung off `data` — the ABI-encoded revert, for a call a contract refused.
  RemoteError(Int, String, Json)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for JsError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
