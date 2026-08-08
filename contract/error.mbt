///|
/// What can go wrong calling a contract: the wallet's problem, the ABI's, or
/// the contract's own refusal.
///
/// The halves are kept apart because they call for different handling. An
/// `Rpc` is the wallet or the node answering — the user rejected the prompt,
/// the node is unreachable — and a dapp already has UI for it. An `Abi` means
/// the contract at that address is not the contract the caller described: a bad
/// address, or an ABI that has drifted from what is deployed. No retry helps.
/// The last three are the contract itself saying no, which is neither: the call
/// was well-formed and it arrived, and what came back is a *reason*.
///
/// ```
/// try @contract.Erc20::new(token).balance_of(wallet, who) catch {
///   Rpc(UserRejected) => "the user said no"
///   Rpc(e) => "the wallet said: \{e}"
///   Abi(e) => "that address is not an ERC-20: \{e}"
///   Revert(reason) => "the contract said: \{reason}"
///   e => "\{e}"
/// } noraise {
///   _ => "fine"
/// }
/// ```
pub(all) suberror ContractError {
  /// The call itself failed: rejected, unreachable, or reverted with nothing
  /// this layer could read.
  Rpc(@provider.ProviderError)
  /// The arguments could not be encoded, or the answer could not be read back
  /// as the types the caller expected.
  Abi(@types.AbiError)
  /// A deployment that did not leave a contract behind: it reverted, its
  /// receipt carries no `contractAddress`, or the creation code it was handed
  /// is not hex.
  Deployment(String)
  /// `Error(string)` — the contract refused on purpose and said why, which is
  /// the message of a `require(cond, "…")` or a `revert("…")`.
  Revert(String)
  /// `Panic(uint256)` — the contract hit one of the checks the compiler
  /// inserts: an overflow, a division by zero, an index out of bounds. Not a
  /// refusal but a bug, and `panic_reason` says which.
  Panic(@bigint.BigInt)
  /// A custom error (`error InsufficientBalance(uint256 have, uint256 want)`).
  ///
  /// `selector` and `data` are always the revert itself; `name` and `args` are
  /// filled in only when the caller passed the matching `ErrorDef`, since
  /// nothing on the wire says what a selector was named.
  CustomError(
    selector~ : @types.Hex,
    name~ : String?,
    args~ : Array[@types.AbiValue],
    data~ : @types.Hex
  )
} derive(Eq)

///|
/// Written out rather than derived from `Debug`, unlike the errors below it:
/// `Panic` has to print what its code *means* and a named `CustomError` has to
/// print its arguments, and neither is something a derived representation can
/// reach.
pub impl Show for ContractError with fn output(self, logger) {
  match self {
    Rpc(e) => logger.write_string("Rpc(\{e})")
    Abi(e) => logger.write_string("Abi(\{e})")
    Deployment(what) => logger.write_string("Deployment(\{what})")
    Revert(reason) => logger.write_string("Revert(\{reason})")
    Panic(code) => logger.write_string("Panic(\{code}: \{panic_reason(code)})")
    CustomError(selector~, name~, args~, ..) =>
      match name {
        // named: spell it the way the ABI declares it
        Some(name) =>
          logger.write_string(
            "CustomError(\{name}(\{args.map(v => v.to_string()).join(", ")}))",
          )
        None => logger.write_string("CustomError(\{selector})")
      }
  }
}

///|
/// One line to put in front of a person, the same question `ProviderError` and
/// `CodecError` answer. The wallet's and the ABI's failures delegate, so a
/// dapp that catches a `ContractError` says the same thing about a declined
/// prompt as one that catches the `ProviderError` directly.
///
/// `Revert` is the interesting one: the string a `require(cond, "…")` carries
/// was written by the contract's author *for this purpose*, so it is passed
/// through as it is.
///
/// ```mbt check
/// test "doc: contract error message" {
///   inspect(
///     @contract.Revert("insufficient allowance").message(),
///     content="insufficient allowance",
///   )
/// }
/// ```
pub fn ContractError::message(self : ContractError) -> String {
  match self {
    Rpc(e) => e.message()
    Abi(e) => e.message()
    Deployment(_) => "The contract could not be deployed."
    Revert(reason) => reason
    Panic(code) => "The contract hit an internal error: \{panic_reason(code)}."
    CustomError(name=Some(name), ..) => "The contract refused: \{name}."
    CustomError(..) => "The contract refused the call."
  }
}

///|
/// Whether making the same call again is worth anything. Only the wallet's
/// failures ever are — a contract that refused refuses again, and an ABI that
/// does not match will not start matching.
pub fn ContractError::is_retryable(self : ContractError) -> Bool {
  match self {
    Rpc(e) => e.is_retryable()
    _ => false
  }
}

///|
/// The EIP-1193 / EIP-1474 code underneath, when the failure came from the
/// wallet or the node. `None` once the ABI layer has read the revert: a decoded
/// `Revert` or `Panic` is no longer a numbered protocol error.
pub fn ContractError::code(self : ContractError) -> Int? {
  match self {
    Rpc(e) => e.code()
    _ => None
  }
}

///|
/// The reason a `require(cond, "…")` or `revert("…")` gave, and `None` for
/// everything else — including a `Panic` or a custom error, which carry no
/// string at all.
///
/// It is the one branch worth pulling out by itself: a dapp that shows nothing
/// else about a failed call usually still wants to show this.
///
/// ```mbt check
/// test "doc: revert reason" {
///   debug_inspect(
///     @contract.Revert("ERC20: transfer amount exceeds balance").revert_reason(),
///     content=(
///       #|Some("ERC20: transfer amount exceeds balance")
///     ),
///   )
/// }
/// ```
pub fn ContractError::revert_reason(self : ContractError) -> String? {
  match self {
    Revert(reason) => Some(reason)
    _ => None
  }
}
