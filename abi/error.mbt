///|
/// What can go wrong translating between MoonBit values and the contract ABI.
///
/// The three cases are three different mistakes: `InvalidAbiType` is a type
/// that no contract can declare (`uint7`, `bytes33`), `InvalidValue` is a value
/// that does not fit a type that does exist, and `InvalidData` is encoded bytes
/// that cannot be read back as the types the caller expected — the only one of
/// the three that a well-written dapp still sees at runtime, since it means the
/// contract answered with something other than what its ABI promised.
///
/// It is `pub(all)` so a layer built on this one can raise an `InvalidData` of
/// its own: a preset that knows a getter must answer a number has the same
/// thing to say when it does not.
///
/// ```
/// try @abi.encode([Uint(8)], [Uint(300N)]) catch {
///   e => inspect(e, content="InvalidValue(uint8 cannot hold 300)")
/// } noraise {
///   _ => fail("expected an error")
/// }
/// ```
pub(all) suberror AbiError {
  /// A type that cannot appear in an ABI: a bit width that is not a multiple
  /// of 8, `bytes0`, a fixed array of negative length.
  InvalidAbiType(String)
  /// A value that does not fit the type it is being encoded as — out of range
  /// for the bit width, the wrong variant, the wrong number of elements.
  InvalidValue(String)
  /// Encoded data that cannot be read back as the expected types: too short,
  /// or an offset or length pointing outside it.
  InvalidData(String)
} derive(Eq)

///|
pub impl Show for AbiError with fn output(self, logger) {
  match self {
    InvalidAbiType(s) => logger.write_string("InvalidAbiType(\{s})")
    InvalidValue(s) => logger.write_string("InvalidValue(\{s})")
    InvalidData(s) => logger.write_string("InvalidData(\{s})")
  }
}
