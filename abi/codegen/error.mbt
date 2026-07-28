///|
/// What can go wrong turning an ABI document into MoonBit source.
///
/// The three cases separate three different mistakes, and only the last one is
/// the generator's own scope talking. `InvalidJson` is a file that is not an
/// ABI document at all — unparseable, or parseable but not the array of
/// members the ABI spec describes. `InvalidAbi` is a member that no compiler
/// could have emitted: a parameter whose `type` is missing, or a type
/// (`uint7`, `bytes33`) that cannot exist. `InvalidName` is the caller's, not
/// the file's: the struct name asked for is not a MoonBit type identifier.
///
/// A member this generator merely *declines* to translate raises nothing — it
/// is skipped, listed in `Generated::skipped` and noted in the emitted source,
/// so one exotic function does not cost the caller the other twenty.
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
