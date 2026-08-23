///|
/// A parameter type as a contract's ABI declares it.
///
/// It tells `@abi.encode` how to lay a value out and `@abi.decode` how to read
/// one back: ABI data carries no type tags. `Uint` / `Int` take the bit width
/// and `FixedBytes` the byte count, so `uint256` is `Uint(256)` and `bytes32`
/// is `FixedBytes(32)`. It lives here because `abi` and `eip712` both need it.
///
/// ```
/// // (address to, uint256 amount)
/// let inputs = [@types.AbiType::Address, Uint(256)]
/// // string[] — a dynamic array of dynamic elements
/// let names = @types.AbiType::Array(String)
/// ```
pub(all) enum AbiType {
  /// `uintN`, where `N` is a multiple of 8 in `8..=256`.
  Uint(Int)
  /// `intN`, where `N` is a multiple of 8 in `8..=256`.
  Int(Int)
  /// `address` — 20 bytes, right-aligned in its word.
  Address
  /// `bool` — a word holding 0 or 1.
  Bool
  /// `bytesN`, where `N` is in `1..=32`; left-aligned in its word.
  FixedBytes(Int)
  /// `bytes` — a dynamic byte string.
  Bytes
  /// `string` — a dynamic byte string carrying UTF-8.
  String
  /// `T[]` — a dynamic array.
  Array(AbiType)
  /// `T[k]` — a fixed-length array.
  FixedArray(AbiType, Int)
  /// `(T1,T2,…)` — a tuple, which is what a `struct` is on the wire.
  Tuple(Array[AbiType])
} derive(Eq, Debug)

///|
pub impl Show for AbiType with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// One ABI-encoded value, in the MoonBit shape that matches its `AbiType`.
///
/// `pub(all)` because a decoded value is read, not built by the SDK's rules.
/// Encoding takes the type alongside the value, so a `Uint` carries a plain
/// `BigInt` and its width — and its range check — comes from the `AbiType`.
///
/// ```
/// let args : Array[@types.AbiValue] = [
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
  Address(Address)
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

///|
/// `bits` if `uintN` / `intN` can have that width, `InvalidAbiType` otherwise.
/// `what` names which of the two is being checked, so the message spells the
/// type the caller wrote.
pub fn AbiType::checked_bits(bits : Int, what~ : String) -> Int raise AbiError {
  guard @codec.is_valid_bits(bits) else {
    raise InvalidAbiType(
      "\{what}\{bits}: width must be a multiple of 8 in 8..=256",
    )
  }
  bits
}

///|
/// `n` if `bytesN` can have that size, `InvalidAbiType` otherwise.
pub fn AbiType::checked_bytes_size(n : Int) -> Int raise AbiError {
  guard @codec.is_valid_bytes_size(n) else {
    raise InvalidAbiType("bytes\{n}: size must be in 1..=32")
  }
  n
}

///|
/// `k` if `T[k]` can have that length, `InvalidAbiType` otherwise.
pub fn AbiType::checked_array_size(k : Int) -> Int raise AbiError {
  guard @codec.is_valid_array_size(k) else {
    raise InvalidAbiType("T[\{k}]: length cannot be negative")
  }
  k
}

///|
/// `n` if a `uintN` of this width holds it, `AbiError` otherwise — the width
/// rule and the range rule in the order a caller needs them, since `uint7` is
/// wrong about the type and `uint8(300)` about the value.
pub fn AbiValue::checked_uint(n : BigInt, bits~ : Int) -> BigInt raise AbiError {
  let bits = AbiType::checked_bits(bits, what="uint")
  guard @codec.fits_uint(n, bits~) else {
    raise InvalidValue("uint\{bits} cannot hold \{n}")
  }
  n
}

///|
/// `n` if an `intN` of this width holds it, `AbiError` otherwise.
pub fn AbiValue::checked_int(n : BigInt, bits~ : Int) -> BigInt raise AbiError {
  let bits = AbiType::checked_bits(bits, what="int")
  guard @codec.fits_int(n, bits~) else {
    raise InvalidValue("int\{bits} cannot hold \{n}")
  }
  n
}

///|
/// The canonical name the ABI spec gives this type — what a function signature
/// is spelled with, and therefore what the selector is hashed from.
///
/// It validates as it renders: hashing `uint7(…)` would produce a selector no
/// contract answers to, which is worse than raising.
///
/// ```mbt check
/// test "doc: abi type" {
///   inspect(@types.AbiType::Uint(256).name(), content="uint256")
///   inspect(
///     @types.AbiType::Array(Tuple([Address, Bool])).name(),
///     content="(address,bool)[]",
///   )
/// }
/// ```
pub fn AbiType::name(self : AbiType) -> String raise AbiError {
  match self {
    Uint(bits) => "uint\{AbiType::checked_bits(bits, what="uint")}"
    Int(bits) => "int\{AbiType::checked_bits(bits, what="int")}"
    Address => "address"
    Bool => "bool"
    FixedBytes(n) => "bytes\{AbiType::checked_bytes_size(n)}"
    Bytes => "bytes"
    String => "string"
    Array(elem) => "\{elem.name()}[]"
    FixedArray(elem, k) => "\{elem.name()}[\{AbiType::checked_array_size(k)}]"
    Tuple(elems) => {
      let parts = []
      for elem in elems {
        parts.push(elem.name())
      }
      "(" + parts.join(",") + ")"
    }
  }
}

///|
/// Whether a value of this type is written as an offset into the tail rather
/// than inline in the head. Everything with a length the type does not fix is
/// dynamic, and a compound is dynamic as soon as one of its parts is.
pub fn AbiType::is_dynamic(self : AbiType) -> Bool {
  match self {
    Bytes | String | Array(_) => true
    FixedArray(elem, _) => elem.is_dynamic()
    Tuple(elems) => elems.iter().any(elem => elem.is_dynamic())
    _ => false
  }
}

///|
/// How many hex digits this type occupies in the head of the block it belongs
/// to: one word for a dynamic type (its offset) and for every scalar, and the
/// flattened size of a static compound, which is written inline.
pub fn AbiType::head_digits(self : AbiType) -> Int {
  if self.is_dynamic() {
    return @codec.WORD_DIGITS
  }
  match self {
    FixedArray(elem, k) => elem.head_digits() * k
    Tuple(elems) =>
      elems.iter().fold(init=0, (sum, elem) => sum + elem.head_digits())
    _ => @codec.WORD_DIGITS
  }
}
