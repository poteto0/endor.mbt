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
/// How wide one ABI word is. Everything the ABI encodes — and everything
/// EIP-712 hashes — is laid out in words this size, so both the byte-level
/// encoder in `typed_data_digest.mbt` and the digit count below start here.
const WORD_BYTES = 32

///|
/// How many hex digits one ABI word takes. `abi/` works in hex digits
/// throughout — `Hex` is a hex string, so staying in that alphabet keeps
/// encoding and decoding to slicing rather than byte arithmetic. It is public
/// because both layers count in these digits: `AbiType::head_digits` here,
/// every word `abi/` writes there.
pub const WORD_DIGITS : Int = WORD_BYTES * 2

///|
/// Whether `bits` is a width `uintN` / `intN` can actually have.
///
/// This and the four below are the ABI's word rules as plain predicates, so the
/// one statement of each rule serves every caller: the `checked_…` functions
/// turn them into an `AbiError`, EIP-712 turns two of them into a `CodecError`
/// naming the field, and `TypedData::classify_elementary` only asks the
/// question (a type name it does not recognize is not an error — it is a struct
/// name).
fn is_valid_bits(bits : Int) -> Bool {
  bits >= 8 && bits <= 256 && bits % 8 == 0
}

///|
/// Whether `n` is a size `bytesN` can actually have. `bytes0` is not a type;
/// the empty dynamic `bytes` is.
fn is_valid_bytes_size(n : Int) -> Bool {
  n >= 1 && n <= WORD_BYTES
}

///|
/// Whether `k` is a length `T[k]` can actually have.
fn is_valid_array_size(k : Int) -> Bool {
  k >= 0
}

///|
/// Whether a `uintN` of this width holds `n`.
fn fits_uint(n : BigInt, bits~ : Int) -> Bool {
  n >= 0N && n < two_pow(bits)
}

///|
/// Whether an `intN` of this width holds `n` — two's complement, so the range
/// is one wider below zero than above.
fn fits_int(n : BigInt, bits~ : Int) -> Bool {
  let half = two_pow(bits - 1)
  n >= -half && n < half
}

///|
/// `bits` if `uintN` / `intN` can have that width, `InvalidAbiType` otherwise.
/// `what` names which of the two is being checked, so the message spells the
/// type the caller wrote.
pub fn AbiType::checked_bits(bits : Int, what~ : String) -> Int raise AbiError {
  guard is_valid_bits(bits) else {
    raise InvalidAbiType(
      "\{what}\{bits}: width must be a multiple of 8 in 8..=256",
    )
  }
  bits
}

///|
/// `n` if `bytesN` can have that size, `InvalidAbiType` otherwise.
pub fn AbiType::checked_bytes_size(n : Int) -> Int raise AbiError {
  guard is_valid_bytes_size(n) else {
    raise InvalidAbiType("bytes\{n}: size must be in 1..=32")
  }
  n
}

///|
/// `k` if `T[k]` can have that length, `InvalidAbiType` otherwise.
pub fn AbiType::checked_array_size(k : Int) -> Int raise AbiError {
  guard is_valid_array_size(k) else {
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
  guard fits_uint(n, bits~) else {
    raise InvalidValue("uint\{bits} cannot hold \{n}")
  }
  n
}

///|
/// `n` if an `intN` of this width holds it, `AbiError` otherwise.
pub fn AbiValue::checked_int(n : BigInt, bits~ : Int) -> BigInt raise AbiError {
  let bits = AbiType::checked_bits(bits, what="int")
  guard fits_int(n, bits~) else {
    raise InvalidValue("int\{bits} cannot hold \{n}")
  }
  n
}

///|
/// `2^bits`, the modulus a `uintN` lives in — and, one bit down, the bound its
/// signed counterpart is symmetric around.
fn two_pow(bits : Int) -> BigInt {
  1N << bits
}

///|
/// One word's bits read as a signed value: the top bit is the sign, so anything
/// at or above `2^255` is that much below zero (two's complement).
///
/// A narrower `intN` is sign-extended to the whole word on the wire, so the
/// width never enters here — which is why `abi`'s `int8` and EIP-712's `int256`
/// can share one function.
pub fn word_to_signed(val : BigInt) -> BigInt {
  if val >= two_pow(WORD_BITS - 1) {
    val - two_pow(WORD_BITS)
  } else {
    val
  }
}

///|
/// A signed value as the word that spells it: unchanged if it is already
/// non-negative, `val + 2^256` otherwise.
pub fn word_to_unsigned(val : BigInt) -> BigInt {
  if val < 0N {
    val + two_pow(WORD_BITS)
  } else {
    val
  }
}

///|
/// How many bits one word holds — the width every value on the wire ends up at.
const WORD_BITS : Int = WORD_BYTES * 8

///|
/// The canonical name the ABI spec gives this type — what a function signature
/// is spelled with, and therefore what the selector is hashed from.
///
/// It validates as it renders, because a type that cannot exist has no
/// canonical name: hashing `uint7(…)` would produce a selector no contract
/// answers to, which is worse than raising.
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
    return WORD_DIGITS
  }
  match self {
    FixedArray(elem, k) => elem.head_digits() * k
    Tuple(elems) =>
      elems.iter().fold(init=0, (sum, elem) => sum + elem.head_digits())
    _ => WORD_DIGITS
  }
}
