///|
/// The `data` of a deployment: creation code with its constructor arguments
/// ABI-encoded behind it.
///
/// `@abi.encode_call` minus the selector, and the missing selector is the point:
/// a constructor has no name, so the arguments are simply appended to the code.
/// A constructor taking nothing leaves the creation code exactly as it was.
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
/// be mined — `eth_sendTransaction` with `to` left out and `deployment_data` in
/// its place. `value` is the ether the constructor is handed.
///
/// The address the code will live at is in the receipt, which is what `deploy`
/// waits for; use this one when the wait belongs to the caller.
pub async fn[P : @provider.Provider] send_deployment(
  provider : P,
  from~ : @types.Address,
  bytecode~ : @types.Hex,
  inputs? : Array[@abi.AbiType],
  args? : Array[@abi.AbiValue],
  value? : @types.Wei,
  errors? : Array[ErrorDef] = [],
) -> @types.TxHash raise ContractError {
  let data = deployment_data(bytecode~, inputs?, args?)
  let request = @types.TransactionRequest::new(from, data~, value?)
  @provider.send_transaction(provider, request) catch {
    e => raise revert_error(e, errors~)
  }
}

///|
/// Deploy `bytecode`, wait for it to be mined, and answer with the `Contract`
/// now at the address it was mined to.
///
/// The three waiting knobs are `wait_for_receipt`'s own, passed straight through
/// with their defaults. A deployment that reverted has a receipt too — and no
/// `contractAddress` — so both are raised as `Deployment`.
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
  errors? : Array[ErrorDef] = [],
  confirmations? : Int,
  timeout? : Int,
  poll_interval? : Int,
) -> Contract raise ContractError {
  let hash = send_deployment(
    provider,
    from~,
    bytecode~,
    inputs?,
    args?,
    value?,
    errors~,
  )
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
  Contract::new(at, errors~)
}
