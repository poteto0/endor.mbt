///|
/// The single number a getter answered with.
///
/// `Contract::call` answers with an `Array[AbiValue]`, since a function may
/// return anything; a preset that knows better should not make every call site
/// pattern-match. An answer that does not decode as one number is an address
/// that is not the token it was taken for, so it names the getter that was asked.
///
/// ```
/// async fn[P : @provider.Provider] supply(
///   p : P,
///   at : @endor.Address,
/// ) -> BigInt raise @contract.ContractError {
///   @contract.uint_answer(
///     @contract.Contract::new(at).call(p, name="totalSupply", outputs=[Uint(256)]),
///     what="totalSupply",
///   )
/// }
/// ```
pub fn uint_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> BigInt raise ContractError {
  guard values is [Uint(n)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer a number"))
  }
  n
}

///|
/// The single signed number a getter answered with.
///
/// Deliberately not folded into `uint_answer`: `uint256` and `int256` are the
/// same thirty-two bytes and differ only in how the top bit is read, so
/// accepting either would silently turn a large positive number negative.
pub fn int_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> BigInt raise ContractError {
  guard values is [Int(n)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer a signed number"))
  }
  n
}

///|
/// The single string a getter answered with.
///
/// The one helper whose type is dynamic: a `string` is an offset and a length
/// pointing into the tail of the answer, so an address that is not the contract
/// the caller described fails here far more often than it does for a number —
/// any 32 bytes decode as a `uint256`, and almost none decode as a `string`.
pub fn string_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> String raise ContractError {
  guard values is [String(s)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer a string"))
  }
  s
}

///|
/// The single boolean a getter answered with.
///
/// Worth having even though a `bool` is a `uint256` that is 0 or 1: reading it
/// through `uint_answer` would hand the caller a `BigInt` to compare against
/// zero, and `@abi.decode` has already done that comparison — including
/// rejecting the word that is neither.
pub fn bool_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> Bool raise ContractError {
  guard values is [Bool(b)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer a boolean"))
  }
  b
}

///|
/// The single run of bytes a getter answered with — `bytes`, or any `bytesN`.
///
/// The width has already been checked: `bytes32` in the caller's `outputs` is
/// what makes `@abi.decode` refuse another length, and re-deciding it here would
/// let the two disagree. What is left is that the answer was one value at all.
pub fn bytes_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> Bytes raise ContractError {
  guard values is [Bytes(b)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer bytes"))
  }
  b
}

///|
/// The single address a getter answered with.
///
/// The answer is an `Address`, not a `Hex`, so the twelve zero bytes an address
/// is right-aligned in have already been checked rather than trimmed — a word
/// with anything in the top twelve bytes is not an address, and a getter
/// answering one is a getter the caller has misidentified.
pub fn address_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> @types.Address raise ContractError {
  guard values is [Address(a)] else {
    raise Abi(@types.InvalidData("\{what}() did not answer an address"))
  }
  a
}
