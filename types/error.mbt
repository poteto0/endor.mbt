///|
/// Errors raised when parsing or validating on-the-wire representations (hex
/// strings, JSON) into domain types.
///
/// It is `pub(all)` for the same reason `AbiError` is: a layer built on the
/// domain types validates the wire the same way and has the same four things to
/// say about it. `@eip712` raises `InvalidJson` for a document whose shape does
/// not match what it declares, and `InvalidLength` for a number that does not
/// fit the width its field is declared at.
///
/// ```
/// try @types.Address::from_string("nope") catch {
///   e => inspect(e, content="InvalidHex(nope)")
/// } noraise {
///   _ => fail("expected an error")
/// }
/// ```
pub(all) suberror CodecError {
  /// The string is not a valid `0x`-prefixed hex value.
  InvalidHex(String)
  /// The value has the wrong byte length for the target type.
  InvalidLength(String)
  /// The JSON shape did not match what the decoder expected.
  InvalidJson(String)
  /// The value carries a self-check that does not match its own contents —
  /// an address whose casing is not its EIP-55 checksum, say.
  InvalidChecksum(String)
} derive(Eq)

///|
pub impl Show for CodecError with fn output(self, logger) {
  match self {
    InvalidHex(s) => logger.write_string("InvalidHex(\{s})")
    InvalidLength(s) => logger.write_string("InvalidLength(\{s})")
    InvalidJson(s) => logger.write_string("InvalidJson(\{s})")
    InvalidChecksum(s) => logger.write_string("InvalidChecksum(\{s})")
  }
}

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
/// It lives here rather than in `abi/` for the same reason `AbiType` does: the
/// rules about ABI types are checked at both levels — `AbiType::name` here,
/// `@abi.encode` / `@abi.decode` there — and `abi` depends on `types`, so the
/// error both raise has to live at this level. `abi` re-exports it
/// (`@abi.AbiError`).
///
/// It is `pub(all)` so a layer built on this one can raise an `InvalidData` of
/// its own: a preset that knows a getter must answer a number has the same
/// thing to say when it does not.
///
/// ```
/// try @types.AbiValue::checked_uint(300N, bits=8) |> ignore catch {
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
