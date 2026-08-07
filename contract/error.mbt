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
  /// A deployment was mined but left no contract behind: it reverted, or its
  /// receipt carries no `contractAddress`.
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
