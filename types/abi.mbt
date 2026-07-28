///|
/// A parameter type as a contract's ABI declares it.
///
/// It is what tells `@abi.encode` how to lay a value out and `@abi.decode` how
/// to read one back: ABI data carries no type tags, so the schema has to come
/// from the caller. `Uint` / `Int` take the bit width and `FixedBytes` the
/// byte count, so `uint256` is `Uint(256)`, `uint8` is `Uint(8)` and `bytes32`
/// is `FixedBytes(32)`.
///
/// It lives here rather than in `abi/` because EIP-712's own atomic types
/// (see `TypedData`'s digest methods) are the same set by design — EIP-712
/// hashes its atomic values the way the ABI encodes them — and `abi` depends
/// on `types`, not the other way around, so a type both layers need has to
/// live at this level. `abi` re-exports it (`@abi.AbiType`), and its own
/// package still owns everything ABI-specific built on top: `name`,
/// `is_dynamic`, `head_digits`, `encode`, `decode`.
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
/// It is `pub(all)` because a decoded value is read, not built by the SDK's
/// rules: `@abi.decode` answers with these and the caller pattern-matches
/// them. Encoding takes the type alongside the value, so a `Uint` carries a
/// plain `BigInt` and its width comes from the `AbiType` it is paired with —
/// that is also where an out-of-range value is caught.
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
/// How many hex digits one ABI word takes — used only by `AbiType::head_digits`
/// here; `abi/` keeps its own copy for the encoding it does with them.
const WORD_DIGITS = 64

///|
/// A bit width `uintN` / `intN` can actually have.
fn validate_bits(bits : Int, what : String) -> Int raise CodecError {
  guard bits >= 8 && bits <= 256 && bits % 8 == 0 else {
    raise InvalidLength(
      "\{what}\{bits}: width must be a multiple of 8 in 8..=256",
    )
  }
  bits
}

///|
/// A size `bytesN` can actually have. `bytes0` is not a type; the empty
/// dynamic `bytes` is.
fn validate_bytes_size(n : Int) -> Int raise CodecError {
  guard n >= 1 && n <= 32 else {
    raise InvalidLength("bytes\{n}: size must be in 1..=32")
  }
  n
}

///|
/// A length `T[k]` can actually have.
fn validate_array_size(k : Int) -> Int raise CodecError {
  guard k >= 0 else {
    raise InvalidLength("T[\{k}]: length cannot be negative")
  }
  k
}

///|
/// The canonical name the ABI spec gives this type — what a function signature
/// is spelled with, and therefore what the selector is hashed from.
///
/// It validates as it renders, because a type that cannot exist has no
/// canonical name: hashing `uint7(…)` would produce a selector no contract
/// answers to, which is worse than raising. This raises `CodecError` rather
/// than `abi`'s own `AbiError`: `abi` depends on `types`, not the other way
/// round, so the error a `types`-level check raises has to be `types`' own.
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
pub fn AbiType::name(self : AbiType) -> String raise CodecError {
  match self {
    Uint(bits) => "uint\{validate_bits(bits, "uint")}"
    Int(bits) => "int\{validate_bits(bits, "int")}"
    Address => "address"
    Bool => "bool"
    FixedBytes(n) => "bytes\{validate_bytes_size(n)}"
    Bytes => "bytes"
    String => "string"
    Array(elem) => "\{elem.name()}[]"
    FixedArray(elem, k) => "\{elem.name()}[\{validate_array_size(k)}]"
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
    return WORD_DIGITS
  }
  match self {
    FixedArray(elem, k) => elem.head_digits() * k
    Tuple(elems) =>
      elems.iter().fold(init=0, (sum, elem) => sum + elem.head_digits())
    _ => WORD_DIGITS
  }
}
