///|
/// `types`' word width, aliased because this package counts in these digits at
/// eight call sites.
const WORD_DIGITS : Int = @types.WORD_DIGITS

///|
/// `AbiType` — and the `name` / `is_dynamic` / `head_digits` methods on it, and
/// the `checked_bits` / `checked_bytes_size` / `checked_array_size` rules the
/// encoder validates with — is defined in `types` (see `types/abi.mbt` for why)
/// and re-exported here so existing callers keep spelling it `@abi.AbiType`.
pub using @types {type AbiType}
