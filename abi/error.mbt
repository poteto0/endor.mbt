///|
/// `AbiError` is defined in `types` (see `types/error.mbt` for why) and
/// re-exported here so existing callers keep spelling it `@abi.AbiError`. Its
/// constructors are `types`' own: a caller that raises one of its own spells it
/// `@types.InvalidData(…)`.
pub using @types {type AbiError}
