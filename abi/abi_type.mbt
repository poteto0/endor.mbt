///|
/// How many hex digits one ABI word takes, as `@codec` states it — this package
/// slices in these digits everywhere.
const WORD_DIGITS : Int = @codec.WORD_DIGITS

///|
/// `AbiType` — and the `name` / `is_dynamic` / `head_digits` methods on it, and
/// the `checked_bits` / `checked_bytes_size` / `checked_array_size` rules the
/// encoder validates with — is defined in `types` (see `types/abi.mbt` for why)
/// and re-exported here so existing callers keep spelling it `@abi.AbiType`.
pub using @types {type AbiType}
