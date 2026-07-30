///|
/// The `data` of a deployment: creation code with its constructor arguments
/// ABI-encoded behind it.
///
/// This is `@abi.encode_call` minus the selector, and the missing selector is
/// the whole point: a constructor has no name, so there is nothing to hash and
/// the arguments are simply appended to the code that the EVM runs. A
/// constructor taking nothing therefore leaves the creation code exactly as it
/// was.
///
/// ```
/// let data = @contract.deployment_data(
///   bytecode=@types.Hex::from_string("0x6080"),
///   inputs=[Uint(256)],
///   args=[Uint(1N)],
/// )
/// inspect(
///   data,
///   content=(
///     "0x6080" +
///     "0000000000000000000000000000000000000000000000000000000000000001"
///   ),
/// )
/// ```
pub fn deployment_data(
  bytecode~ : @types.Hex,
  inputs? : Array[@abi.AbiType] = [],
  args? : Array[@abi.AbiValue] = [],
) -> @types.Hex raise ContractError {
  let arguments = @abi.encode(inputs, args) catch { e => raise Abi(e) }
  bytecode.concat(arguments)
}

///|
/// Broadcast a deployment and answer with its hash, without waiting for it to
/// be mined.
///
/// A transaction with no recipient deploys its `data`, so this is
/// `eth_sendTransaction` with `to` left out and `deployment_data` in its place.
/// `from` is required because somebody has to sign, and `value` is the ether
/// the constructor is handed — a contract whose constructor is not `payable`
/// reverts on a non-zero one.
///
/// The address the code will live at is not available here: it is in the
/// receipt, which is what `deploy` waits for. Use this one when the wait
/// belongs to the caller — a UI that wants the hash to link to a block
/// explorer while the transaction is still pending.
pub async fn[P : @provider.Provider] send_deployment(
  provider : P,
  from~ : @types.Address,
  bytecode~ : @types.Hex,
  inputs? : Array[@abi.AbiType],
  args? : Array[@abi.AbiValue],
  value? : @types.Wei,
) -> @types.TxHash raise ContractError {
  let data = deployment_data(bytecode~, inputs?, args?)
  let request = @types.TransactionRequest::new(from, data~, value?)
  @provider.send_transaction(provider, request) catch {
    e => raise Rpc(e)
  }
}

///|
/// Deploy `bytecode`, wait for it to be mined, and answer with the `Contract`
/// now at the address it was mined to.
///
/// The three waiting knobs are `wait_for_receipt`'s own — `confirmations`
/// blocks to wait past the one that mined it, `timeout` and `poll_interval` in
/// milliseconds — and are passed straight through, defaults included, so the
/// wait is described in one place rather than in two that can drift.
///
/// A deployment that reverted has a receipt too — and a receipt with no
/// `contractAddress` — so both are raised as `Deployment` rather than folded
/// into a missing address the caller has to notice for themselves.
///
/// ```
/// async fn[P : @provider.Provider] put_it_on_chain(
///   p : P,
///   me : @endor.Address,
///   code : @endor.Hex,
/// ) -> @endor.Address raise @contract.ContractError {
///   let deployed = @contract.deploy(p, from=me, bytecode=code, inputs=[Uint(256)], args=[
///     Uint(1000N),
///   ])
///   deployed.address()
/// }
/// ```
pub async fn[P : @provider.Provider] deploy(
  provider : P,
  from~ : @types.Address,
  bytecode~ : @types.Hex,
  inputs? : Array[@abi.AbiType],
  args? : Array[@abi.AbiValue],
  value? : @types.Wei,
  confirmations? : Int,
  timeout? : Int,
  poll_interval? : Int,
) -> Contract raise ContractError {
  let hash = send_deployment(provider, from~, bytecode~, inputs?, args?, value?)
  let receipt = @provider.wait_for_receipt(
    provider,
    hash,
    confirmations?,
    timeout?,
    poll_interval?,
  ) catch {
    e => raise Rpc(e)
  }
  guard receipt.status is Success else {
    raise Deployment("deployment \{hash} reverted")
  }
  guard receipt.contract_address is Some(at) else {
    raise Deployment("receipt of \{hash} carries no contractAddress")
  }
  Contract::new(at)
}
