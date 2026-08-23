///|
/// A contract at an address, called through its ABI.
///
/// The ABI layer on top of the typed RPC helpers: `call` is `eth_call` with the
/// arguments encoded and the answer decoded, `send` is `eth_sendTransaction`
/// with them encoded. Each call names the function it makes, so the type
/// describing the contract stays in the caller's code, not a runtime registry.
///
/// ```
/// async fn[P : @provider.Provider] answer(
///   p : P,
///   at : @endor.Address,
/// ) -> BigInt raise @contract.ContractError {
///   let values = @contract.Contract::new(at).call(
///     p,
///     name="answer",
///     outputs=[Uint(256)],
///   )
///   guard values is [Uint(n)] else { return 0N }
///   n
/// }
/// ```
pub struct Contract {
  priv at : @types.Address
  priv errors : Array[ErrorDef]
} derive(Eq, @debug.Debug)

///|
/// Point at a deployed contract.
///
/// `errors` are the contract's own `error` declarations, the one thing worth
/// registering up front: a revert names an error by selector alone. Without them
/// a custom error still comes back, but its arguments stay encoded.
pub fn Contract::new(
  address : @types.Address,
  errors? : Array[ErrorDef] = [],
) -> Contract {
  Contract::{ at: address, errors }
}

///|
/// The address the calls go to.
pub fn Contract::address(self : Contract) -> @types.Address {
  self.at
}

///|
/// Call a function that reads: encode the arguments, `eth_call`, decode the
/// answer as `outputs`.
///
/// It prompts no one and costs nothing, so `from` is only worth setting for a
/// contract that reads `msg.sender`. The three steps are spelled out because a
/// batched read is the same encode and decode with another request in between.
pub async fn[P : @provider.Provider] Contract::call(
  self : Contract,
  provider : P,
  name~ : String,
  inputs? : Array[@abi.AbiType] = [],
  args? : Array[@abi.AbiValue] = [],
  outputs? : Array[@abi.AbiType] = [],
  from? : @types.Address,
  block? : @types.BlockTag,
) -> Array[@abi.AbiValue] raise ContractError {
  let prepared = self.prepare(name~, inputs~, args~, outputs~)
  let request = @types.CallRequest::new(
    prepared.target(),
    from?,
    data=prepared.data(),
  )
  let answer = @provider.call(provider, request, block?) catch {
    e => raise revert_error(e, errors=self.errors)
  }
  prepared.decode(answer)
}

///|
/// Call a function that writes: encode the arguments and broadcast them as a
/// transaction.
///
/// The answer is a `TxHash` — a broadcast transaction has not run yet, so what
/// it *did* is in its receipt. `from` is required because somebody has to sign.
pub async fn[P : @provider.Provider] Contract::send(
  self : Contract,
  provider : P,
  from~ : @types.Address,
  name~ : String,
  inputs? : Array[@abi.AbiType] = [],
  args? : Array[@abi.AbiValue] = [],
  value? : @types.Wei,
) -> @types.TxHash raise ContractError {
  let data = @abi.encode_call(name~, inputs~, args~) catch { e => raise Abi(e) }
  let request = @types.TransactionRequest::new(from, to=self.at, data~, value?)
  @provider.send_transaction(provider, request) catch {
    e => raise revert_error(e, errors=self.errors)
  }
}
