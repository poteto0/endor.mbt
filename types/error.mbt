///|
/// Errors raised when parsing or validating on-the-wire representations (hex
/// strings, JSON) into domain types.
///
/// The variants are kept apart by *what is wrong with the value* rather than by
/// which decoder noticed: `InvalidHex` / `InvalidLength` / `InvalidChecksum` /
/// `InvalidJson` are about the **form**, `InvalidValue` about the **meaning**.
///
/// ```
/// try @types.Address::from_string("nope") catch {
///   e => inspect(e, content="InvalidHex(\"nope\")")
/// } noraise {
///   _ => fail("expected an error")
/// }
/// ```
pub(all) suberror CodecError {
  /// The string is not a valid `0x`-prefixed hex value.
  InvalidHex(String)
  /// The value has the wrong length for what it must be: twenty bytes for an
  /// address, thirty-two for a hash, `n` items for a `T[n]`. Counting, not
  /// range — a number too large for its width is `InvalidValue`.
  InvalidLength(String)
  /// The JSON shape did not match what the decoder expected: a member that is
  /// absent, or of the wrong kind.
  InvalidJson(String)
  /// The value carries a self-check that does not match its own contents —
  /// an address whose casing is not its EIP-55 checksum, say.
  InvalidChecksum(String)
  /// The string is not a decimal amount the target can hold: not a number at
  /// all, finer than the `decimals` it is being read at, or read at a scale
  /// that is not one.
  InvalidDecimal(String)
  /// The value is well-formed and still wrong: out of the range its type or
  /// its field allows, or naming something the document never defines. The
  /// form is fine; what it says is not.
  InvalidValue(String)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the variant list stays
/// the single source of truth for how errors print.
pub impl Show for CodecError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One line to put in front of a person, with no variant name and no decoder
/// internals in it. `Show` is the developer's view of the same error.
pub fn CodecError::message(self : CodecError) -> String {
  match self {
    InvalidHex(_) => "That is not a valid hex value."
    InvalidLength(_) => "That value is the wrong length."
    InvalidJson(_) => "That data is not in the expected format."
    InvalidChecksum(_) =>
      "That address looks mistyped — its checksum does not match."
    InvalidDecimal(_) => "That is not an amount that can be read."
    InvalidValue(_) => "That value is out of range."
  }
}

///|
/// Never: a value that does not parse does not parse the second time either.
/// It is here so a caller can ask any of the SDK's errors the same question
/// without first knowing which one it caught.
pub fn CodecError::is_retryable(_self : CodecError) -> Bool {
  false
}

///|
/// What can go wrong translating between MoonBit values and the contract ABI.
///
/// `InvalidAbiType` is a type no contract can declare (`uint7`), `InvalidValue`
/// a value that does not fit one that exists, and `InvalidData` encoded bytes
/// that cannot be read back — the one a well-written dapp still sees at
/// runtime, since it means the contract broke its own ABI.
///
/// ```
/// try @types.AbiValue::checked_uint(300N, bits=8) |> ignore catch {
///   e => inspect(e, content="InvalidValue(\"uint8 cannot hold 300\")")
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
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, for the same reason
/// `CodecError` does.
pub impl Show for AbiError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One line to put in front of a person. See `CodecError::message`.
pub fn AbiError::message(self : AbiError) -> String {
  match self {
    InvalidAbiType(_) => "That is not a type a contract can declare."
    InvalidValue(_) => "That value does not fit the type it is being sent as."
    InvalidData(_) =>
      "The contract answered with something other than what its ABI describes."
  }
}

///|
/// Never: an ABI that does not match is not going to match on a second call.
/// See `CodecError::is_retryable`.
pub fn AbiError::is_retryable(_self : AbiError) -> Bool {
  false
}
