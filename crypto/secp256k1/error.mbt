///|
/// Why a run of bytes is not a key, or a signature.
///
/// `InvalidLength` is about the **form** — a scalar is 32 bytes, a signature 65
/// — while `InvalidKey` and `InvalidSignature` are about the **value**. It lives
/// here rather than in `types/` because this package sits below the domain
/// types, and the layers only point one way.
///
/// ```
/// try @secp256k1.PrivateKey::from_bytes(Bytes::make(32, b'\x00')) |> ignore catch {
///   e => inspect(e, content="InvalidKey(\"zero\")")
/// } noraise {
///   _ => fail("expected an error")
/// }
/// ```
pub(all) suberror CurveError {
  /// A run of bytes of the wrong width: a scalar or a digest that is not 32
  /// bytes, a signature that is not 65. For a key it is checked only when the
  /// caller asked for the exact width.
  InvalidLength(String)
  /// A scalar outside `[1, N)`, which is every scalar that is not a key.
  InvalidKey(String)
  /// A signature whose halves are out of range, whose `s` is the high one of
  /// the pair EIP-2 forbids, or which recovers no public key at all.
  InvalidSignature(String)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for CurveError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One line to put in front of a person, with no variant name in it. `Show` is
/// the developer's view of the same error.
pub fn CurveError::message(self : CurveError) -> String {
  match self {
    InvalidLength(_) => "That value is the wrong length."
    InvalidKey(_) => "That is not a valid private key."
    InvalidSignature(_) => "That is not a valid signature."
  }
}

///|
/// Never: bytes that are not a key, or not a signature, are not one the second
/// time either.
pub fn CurveError::is_retryable(_self : CurveError) -> Bool {
  false
}
