///|
/// One ABI-encoded value, in the MoonBit shape that matches its `AbiType`.
///
/// It is `pub(all)` because a decoded value is read, not built by the SDK's
/// rules: `decode` answers with these and the caller pattern-matches them.
/// Encoding takes the type alongside the value, so a `Uint` carries a plain
/// `BigInt` and its width comes from the `AbiType` it is paired with — that is
/// also where an out-of-range value is caught.
///
/// ```
/// let args : Array[@abi.AbiValue] = [
///   Address(@types.Address::from_string("0x0000000000000000000000000000000000000001")),
///   Uint(1000N),
/// ]
/// ```
pub(all) enum AbiValue {
  /// For `uintN`. Must be non-negative and below `2^N`.
  Uint(BigInt)
  /// For `intN`. Two's complement on the wire; negative values are fine here.
  Int(BigInt)
  /// For `address`.
  Address(@types.Address)
  /// For `bool`.
  Bool(Bool)
  /// For `bytesN` — exactly `N` bytes — and for `bytes`, any length.
  Bytes(Bytes)
  /// For `string`. Encoded as its UTF-8 bytes.
  String(String)
  /// For `T[]` and `T[k]`.
  Array(Array[AbiValue])
  /// For a tuple, i.e. a `struct`.
  Tuple(Array[AbiValue])
} derive(Eq, Debug)

///|
pub impl Show for AbiValue with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
