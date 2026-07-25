///|
/// Errors raised by codecs in the `types` package when parsing or validating
/// on-the-wire representations (hex strings, JSON) into domain types.
///
/// ```
/// try @types.Address::from_string("nope") catch {
///   e => inspect(e, content="InvalidHex(nope)")
/// } noraise {
///   _ => fail("expected an error")
/// }
/// ```
pub suberror CodecError {
  /// The string is not a valid `0x`-prefixed hex value.
  InvalidHex(String)
  /// The value has the wrong byte length for the target type.
  InvalidLength(String)
  /// The JSON shape did not match what the decoder expected.
  InvalidJson(String)
} derive(Eq)

///|
pub impl Show for CodecError with fn output(self, logger) {
  match self {
    InvalidHex(s) => logger.write_string("InvalidHex(\{s})")
    InvalidLength(s) => logger.write_string("InvalidLength(\{s})")
    InvalidJson(s) => logger.write_string("InvalidJson(\{s})")
  }
}
