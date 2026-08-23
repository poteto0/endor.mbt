///|
/// What can go wrong turning an ABI document into MoonBit source.
///
/// `InvalidJson` is a file that is not an ABI document at all; `InvalidAbi` a
/// member no compiler could have emitted; `InvalidName` the caller's, not the
/// file's. A member this generator merely *declines* to translate raises
/// nothing — it is skipped and listed in `Generated::skipped`.
///
/// ```
/// try @codegen.generate("Erc20", "not json") catch {
///   InvalidJson(_) => "that file is not an ABI"
///   e => "\{e}"
/// } noraise {
///   _ => "fine"
/// }
/// ```
pub(all) suberror CodegenError {
  /// The document does not parse as JSON, or is not a JSON array of ABI
  /// members.
  InvalidJson(String)
  /// A member of the array is not a well-formed ABI member: no `type`, a
  /// missing `name`, or a parameter type that cannot exist.
  InvalidAbi(String)
  /// The requested struct name is not a MoonBit type identifier.
  InvalidName(String)
} derive(Eq)

///|
pub impl Show for CodegenError with fn output(self, logger) {
  match self {
    InvalidJson(s) => logger.write_string("InvalidJson(\{s})")
    InvalidAbi(s) => logger.write_string("InvalidAbi(\{s})")
    InvalidName(s) => logger.write_string("InvalidName(\{s})")
  }
}
