///|
/// A contract at an address, called through its ABI.
///
/// It is the ABI layer sitting on top of the typed RPC helpers: `call` is
/// `eth_call` with the arguments encoded and the answer decoded, and `send` is
/// `eth_sendTransaction` with the arguments encoded. Nothing is cached and no
/// ABI is registered up front — each call names the function it makes, which
/// keeps the type describing the contract in the caller's code (or in a preset
/// like `Erc20`) rather than in a runtime registry.
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
/// `errors` are the contract's own `error` declarations, and they are the one
/// thing worth registering up front: a revert names an error by selector alone,
/// so a call cannot be told what it might fail with the way it is told what it
/// returns. Without them a custom error still comes back — as a `CustomError`
/// holding its selector and raw data — but its arguments stay encoded.
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
/// contract that reads `msg.sender`. `block` reads at some other point in the
/// chain's history, exactly as it does for the plain RPC helpers.
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
  let data = @abi.encode_call(name~, inputs~, args~) catch { e => raise Abi(e) }
  let request = @types.CallRequest::new(self.at, from?, data~)
  let answer = @provider.call(provider, request, block?) catch {
    e => raise revert_error(e, errors=self.errors)
  }
  @abi.decode(outputs, answer) catch {
    e => raise Abi(e)
  }
}

///|
/// Call a function that writes: encode the arguments and broadcast them as a
/// transaction.
///
/// The answer is a `TxHash`, so what the function returned is not available
/// here — a broadcast transaction has not run yet. What it *did* is in its
/// receipt (`@provider.wait_for_receipt`), and `from` is required because
/// somebody has to sign.
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
