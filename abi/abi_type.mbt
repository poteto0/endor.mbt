///|
/// How many hex digits one ABI word takes. Everything the ABI encodes is laid
/// out in 32-byte words, and this package works in hex digits throughout —
/// `Hex` is a hex string, so staying in that alphabet keeps encoding and
/// decoding to slicing rather than byte arithmetic.
const WORD_DIGITS = 64

///|
/// `AbiType` — and the `name` / `is_dynamic` / `head_digits` methods on it —
/// is defined in `types` (see `types/abi.mbt` for why) and re-exported here so
/// existing callers keep spelling it `@abi.AbiType`.
pub using @types {type AbiType}
