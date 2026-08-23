///|
/// A call encoded but not yet sent.
///
/// `Contract::call` welds an encode, a request and a decode together, and welded
/// together they cannot be bundled. This holds the two halves as a value:
/// `target` and `data` are what a batcher builds its element from, `decode`
/// reads the answer, and the contract's `errors` come along for `revert`.
///
/// ```mbt check
/// test "doc: a call encoded but not sent" {
///   let at = @types.Address::from_string(
///     "0x52908400098527886E0F7030069857D2E4169EE7",
///   )
///   let prepared = @contract.Contract::new(at).prepare(name="answer", outputs=[
///     Uint(256),
///   ])
///   inspect(
///     prepared.target(),
///     content="0x52908400098527886E0F7030069857D2E4169EE7",
///   )
/// }
/// ```
pub struct PreparedCall {
  priv to : @types.Address
  priv calldata : @types.Hex
  priv outputs : Array[@types.AbiType]
  priv errors : Array[ErrorDef]
} derive(Eq, @debug.Debug)

///|
/// Encode a call without making it: everything `call` does before the RPC.
///
/// The arguments to give it are the arguments `call` takes, minus the ones that
/// belong to the request rather than to the function — `from` and `block` are
/// the batch's, not the element's, once several of these travel together.
///
/// ```mbt check
/// test "doc: encoding a call is not making it" {
///   let at = @types.Address::from_string(
///     "0x52908400098527886E0F7030069857D2E4169EE7",
///   )
///   let prepared = @contract.Contract::new(at).prepare(
///     name="balanceOf",
///     inputs=[Address],
///     args=[Address(at)],
///     outputs=[Uint(256)],
///   )
///   inspect(prepared.data().byte_length(), content="36")
/// }
/// ```
pub fn Contract::prepare(
  self : Contract,
  name~ : String,
  inputs? : Array[@types.AbiType] = [],
  args? : Array[@types.AbiValue] = [],
  outputs? : Array[@types.AbiType] = [],
) -> PreparedCall raise ContractError {
  let calldata = @abi.encode_call(name~, inputs~, args~) catch {
    e => raise Abi(e)
  }
  PreparedCall::{ to: self.at, calldata, outputs, errors: self.errors }
}

///|
/// The address this call goes to — the `to` of the `eth_call`, or the `target`
/// of a batch element.
pub fn PreparedCall::target(self : PreparedCall) -> @types.Address {
  self.to
}

///|
/// The calldata: the selector and the encoded arguments, ready to be sent by
/// whoever sends it.
pub fn PreparedCall::data(self : PreparedCall) -> @types.Hex {
  self.calldata
}

///|
/// Read return data as the types this call declared: everything `call` does
/// after the RPC.
///
/// ```mbt check
/// test "doc: reading the answer back" {
///   let at = @types.Address::from_string(
///     "0x52908400098527886E0F7030069857D2E4169EE7",
///   )
///   let prepared = @contract.Contract::new(at).prepare(name="answer", outputs=[
///     Uint(256),
///   ])
///   let answer = @types.Hex::from_string(
///     "0x00000000000000000000000000000000000000000000000000000000000003e8",
///   )
///   debug_inspect(prepared.decode(answer), content="[Uint(1000)]")
/// }
/// ```
pub fn PreparedCall::decode(
  self : PreparedCall,
  return_data : @types.Hex,
) -> Array[@types.AbiValue] raise ContractError {
  @abi.decode(self.outputs, return_data) catch {
    e => raise Abi(e)
  }
}

///|
/// Read raw revert bytes as a `ContractError`, against this call's own error
/// declarations.
///
/// A bundled sub-call's failure arrives as bytes and nothing else, so the
/// JSON-RPC wrapper a plain `eth_call` would have is put back and `revert_error`
/// reads it as any other — a batched failure is identical to a direct one.
///
/// ```mbt check
/// test "doc: what a bundled sub-call refused with" {
///   let at = @types.Address::from_string(
///     "0x52908400098527886E0F7030069857D2E4169EE7",
///   )
///   let prepared = @contract.Contract::new(at).prepare(name="answer")
///   // `require(false, "nope")` — Error(string) with one argument
///   let data = @types.Hex::from_string(
///     "0x08c379a0" +
///     "0000000000000000000000000000000000000000000000000000000000000020" +
///     "0000000000000000000000000000000000000000000000000000000000000004" +
///     "6e6f706500000000000000000000000000000000000000000000000000000000",
///   )
///   inspect(prepared.revert(data), content="Revert(nope)")
/// }
/// ```
pub fn PreparedCall::revert(
  self : PreparedCall,
  data : @types.Hex,
) -> ContractError {
  revert_error(
    @provider.ProviderError::Reverted(
      code=3,
      message="execution reverted",
      data~,
    ),
    errors=self.errors,
  )
}
