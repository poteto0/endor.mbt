///|
/// How many hex digits one ABI word takes. Everything the ABI encodes is laid
/// out in 32-byte words, and this package works in hex digits throughout —
/// `Hex` is a hex string, so staying in that alphabet keeps encoding and
/// decoding to slicing rather than byte arithmetic.
const WORD_DIGITS = 64

///|
/// A parameter type as a contract's ABI declares it.
///
/// It is what tells `encode` how to lay a value out and `decode` how to read
/// one back: ABI data carries no type tags, so the schema has to come from the
/// caller. `Uint` / `Int` take the bit width and `FixedBytes` the byte count,
/// so `uint256` is `Uint(256)`, `uint8` is `Uint(8)` and `bytes32` is
/// `FixedBytes(32)`.
///
/// ```
/// // (address to, uint256 amount)
/// let inputs = [@abi.AbiType::Address, Uint(256)]
/// // string[] — a dynamic array of dynamic elements
/// let names = @abi.AbiType::Array(String)
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
/// The canonical name the ABI spec gives this type — what a function signature
/// is spelled with, and therefore what the selector is hashed from.
///
/// It validates as it renders, because a type that cannot exist has no
/// canonical name: hashing `uint7(…)` would produce a selector no contract
/// answers to, which is worse than raising.
///
/// ```
/// inspect(@abi.AbiType::Uint(256).name(), content="uint256")
/// inspect(@abi.AbiType::Array(Tuple([Address, Bool])).name(), content="(address,bool)[]")
/// ```
pub fn AbiType::name(self : AbiType) -> String raise AbiError {
  match self {
    Uint(bits) => "uint\{check_bits(bits, "uint")}"
    Int(bits) => "int\{check_bits(bits, "int")}"
    Address => "address"
    Bool => "bool"
    FixedBytes(n) => "bytes\{check_bytes_size(n)}"
    Bytes => "bytes"
    String => "string"
    Array(elem) => "\{elem.name()}[]"
    FixedArray(elem, k) => "\{elem.name()}[\{check_array_size(k)}]"
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
/// A bit width `uintN` / `intN` can actually have.
fn check_bits(bits : Int, what : String) -> Int raise AbiError {
  guard bits >= 8 && bits <= 256 && bits % 8 == 0 else {
    raise InvalidAbiType(
      "\{what}\{bits}: width must be a multiple of 8 in 8..=256",
    )
  }
  bits
}

///|
/// A size `bytesN` can actually have. `bytes0` is not a type; the empty
/// dynamic `bytes` is.
fn check_bytes_size(n : Int) -> Int raise AbiError {
  guard n >= 1 && n <= 32 else {
    raise InvalidAbiType("bytes\{n}: size must be in 1..=32")
  }
  n
}

///|
/// A length `T[k]` can actually have.
fn check_array_size(k : Int) -> Int raise AbiError {
  guard k >= 0 else {
    raise InvalidAbiType("T[\{k}]: length cannot be negative")
  }
  k
}

///|
/// Whether a value of this type is written as an offset into the tail rather
/// than inline in the head. Everything with a length the type does not fix is
/// dynamic, and a compound is dynamic as soon as one of its parts is.
fn AbiType::is_dynamic(self : AbiType) -> Bool {
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
fn AbiType::head_digits(self : AbiType) -> Int {
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
