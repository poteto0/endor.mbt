///|
/// One `error` of a contract's ABI: what a `revert` can carry back.
///
/// It is to a revert what `@abi.EventParam` is to a log — the declaration that
/// makes the bytes readable — and it is plain data for the same reason: the
/// caller writes it out of the ABI they already have, or `abi/codegen` emits it
/// alongside the calls.
///
/// ```mbt check
/// test "doc: an error definition" {
///   let insufficient : @contract.ErrorDef = {
///     name: "InsufficientBalance",
///     inputs: [Uint(256), Uint(256)],
///   }
///   inspect(insufficient.selector().unwrap(), content="0xcf479181")
/// }
/// ```
pub(all) struct ErrorDef {
  /// The name Solidity gave it — `error InsufficientBalance(...)`.
  name : String
  /// Its parameters, in declaration order.
  inputs : Array[@types.AbiType]
} derive(Eq, @debug.Debug)

///|
pub impl Show for ErrorDef with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The four bytes a revert of this error starts with, computed the way a
/// function selector is — an error and a function are the same signature hashed
/// the same way.
///
/// `None` when the declared types cannot be spelled at all, so one bad entry in
/// a list of definitions cannot stop the rest from being tried.
pub fn ErrorDef::selector(self : ErrorDef) -> @types.Hex? {
  let signature = @abi.signature(name=self.name, inputs=self.inputs) catch {
    _ => return None
  }
  Some(@abi.selector(signature))
}

///|
/// Read the revert out of a failed call: the same error, with what the contract
/// said decoded when it can be.
///
/// Anything that is not a revert comes back as `Rpc` untouched, and so does a
/// revert with no data. `errors` is the contract's own declarations; without
/// them a custom error still comes back, but its arguments stay encoded.
///
/// ```mbt check
/// test "doc: decode a revert" {
///   // `require(false, "nope")` — Error(string) with one argument
///   let data = @types.Hex::from_string(
///     "0x08c379a0" +
///     "0000000000000000000000000000000000000000000000000000000000000020" +
///     "0000000000000000000000000000000000000000000000000000000000000004" +
///     "6e6f706500000000000000000000000000000000000000000000000000000000",
///   )
///   let failed = @provider.ProviderError::Reverted(
///     code=3,
///     message="execution reverted",
///     data~,
///   )
///   inspect(@contract.revert_error(failed), content="Revert(nope)")
/// }
/// ```
pub fn revert_error(
  error : @provider.ProviderError,
  errors? : Array[ErrorDef] = [],
) -> ContractError {
  guard error is Reverted(data~, ..) else { return Rpc(error) }
  let digits = data.digits()
  // shorter than a selector: nothing names what this revert is
  guard digits.length() >= SELECTOR_DIGITS else { return Rpc(error) }
  let selector_digits = digits[:SELECTOR_DIGITS]
  let selector = @types.Hex::from_digits(selector_digits) catch {
    _ => return Rpc(error)
  }
  let payload = @types.Hex::from_digits(digits[SELECTOR_DIGITS:]) catch {
    _ => return Rpc(error)
  }
  // what the revert says if it can be read; otherwise the revert itself, which
  // still names the error
  let undecoded = () => {
    ContractError::CustomError(selector~, name=None, args=[], data~)
  }
  // a prefix of the digits, which are lower-case by construction: asking
  // `selector` for its own back would copy them out again
  match digits {
    [.. ERROR_STRING_SELECTOR, ..] => {
      guard decoded([String], payload) is Some([String(reason)]) else {
        return undecoded()
      }
      return Revert(reason)
    }
    [.. PANIC_SELECTOR, ..] => {
      guard decoded([Uint(256)], payload) is Some([Uint(code)]) else {
        return undecoded()
      }
      return Panic(code)
    }
    _ => ()
  }
  for def in errors {
    guard def.selector() is Some(s) && s == selector else { continue }
    guard decoded(def.inputs, payload) is Some(args) else { return undecoded() }
    return CustomError(selector~, name=Some(def.name), args~, data~)
  }
  undecoded()
}

///|
/// The values `payload` holds if it holds those types, `None` if it does not.
///
/// A revert whose data does not fit the declaration is not worth raising over:
/// the caller is already handling a failed call, and the selector and the raw
/// bytes still say which error it was.
fn decoded(
  types : Array[@types.AbiType],
  payload : @types.Hex,
) -> Array[@types.AbiValue]? {
  Some(@abi.decode(types, payload) catch { _ => return None })
}

///|
/// Hex digits of the selector every revert but an empty one starts with.
const SELECTOR_DIGITS = 8

///|
/// `Error(string)` — what `require(cond, "…")` and `revert("…")` produce.
///
/// Written out rather than hashed, because these two are the only selectors in
/// Ethereum that are fixed for every contract ever compiled: hashing them on
/// each revert would rediscover a constant. `revert_test.mbt` asserts each is
/// what `@abi.selector` answers, so the shortcut cannot drift from the rule.
const ERROR_STRING_SELECTOR = "08c379a0"

///|
/// `Panic(uint256)` — what the compiler's own checks produce.
const PANIC_SELECTOR = "4e487b71"

///|
/// What a `Panic(uint256)` code means, in the words the Solidity documentation
/// uses for it.
///
/// Every one of them is a bug in the contract rather than something the caller
/// did wrong, which is the whole reason it is worth telling apart from a
/// `require` a contract raised on purpose.
///
/// ```mbt check
/// test "doc: panic reason" {
///   inspect(
///     @contract.panic_reason(0x11N),
///     content="arithmetic overflow or underflow",
///   )
/// }
/// ```
pub fn panic_reason(code : @bigint.BigInt) -> String {
  // every code the compiler assigns is one byte, so anything wider is unknown
  // by the same rule as `0x99` — and narrowing lets the rest read as a table
  guard code >= 0N && code < 0x100N else { return "unknown panic code" }
  match code.to_int() {
    0x00 => "generic compiler-inserted panic"
    0x01 => "assertion failed"
    0x11 => "arithmetic overflow or underflow"
    0x12 => "division or modulo by zero"
    0x21 => "value converted to an enum out of range"
    0x22 => "incorrectly encoded storage byte array"
    0x31 => "pop on an empty array"
    0x32 => "array index out of bounds"
    0x41 => "too much memory allocated, or an array created too large"
    0x51 => "a zero-initialized internal function variable was called"
    _ => "unknown panic code"
  }
}
