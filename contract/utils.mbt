///|
/// The single number a getter answered with.
///
/// A getter whose answer does not decode as one number is an address that is
/// not the token it was taken for — the most likely mistake in this whole
/// package, so it names the getter that was asked.
pub fn uint_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> BigInt raise ContractError {
  guard values is [Uint(n)] else {
    raise Abi(@abi.InvalidData("\{what}() did not answer a number"))
  }
  n
}

///|
/// The single string a getter answered with.
pub fn string_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> String raise ContractError {
  guard values is [String(s)] else {
    raise Abi(@abi.InvalidData("\{what}() did not answer a string"))
  }
  s
}
