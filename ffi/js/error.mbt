///|
pub(all) suberror JsError {
  InvalidEnvelope(String)
  RemoteError(Int, String)
} derive(Eq)
