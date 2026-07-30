///|
/// What can go wrong calling a contract: the wallet's problem, or the ABI's.
///
/// The two halves are kept apart because they call for different handling. An
/// `Rpc` is the wallet or the node answering — the user rejected the prompt,
/// the call reverted — and a dapp already has UI for it. An `Abi` means the
/// contract at that address is not the contract the caller described: a bad
/// address, or an ABI that has drifted from what is deployed. No retry helps.
///
/// ```
/// try @contract.Erc20::new(token).balance_of(wallet, who) catch {
///   Rpc(UserRejected) => "the user said no"
///   Rpc(e) => "the wallet said: \{e}"
///   Abi(e) => "that address is not an ERC-20: \{e}"
/// } noraise {
///   _ => "fine"
/// }
/// ```
pub(all) suberror ContractError {
  /// The call itself failed: rejected, reverted, or unreachable.
  Rpc(@provider.ProviderError)
  /// The arguments could not be encoded, or the answer could not be read back
  /// as the types the caller expected.
  Abi(@types.AbiError)
} derive(Eq)

///|
pub impl Show for ContractError with fn output(self, logger) {
  match self {
    Rpc(e) => logger.write_string("Rpc(\{e})")
    Abi(e) => logger.write_string("Abi(\{e})")
  }
}
