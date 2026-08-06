///|
pub(all) suberror JsError {
  InvalidEnvelope(String)
  /// The wallet rejected the call: its `code` and `message`, and whatever it
  /// hung off `data` — the ABI-encoded revert, for a call a contract refused.
  RemoteError(Int, String, Json)
} derive(Eq)
