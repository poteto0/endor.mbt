///|
/// The canonical signature of a function or an event: its name followed by its
/// parameter types, with no spaces and no parameter names.
///
/// This exact spelling is what gets hashed, so it is where a selector comes
/// from — `transfer(address,uint256)`, never `transfer(address to, uint256)`.
///
/// ```
/// inspect(
///   @abi.signature(name="transfer", inputs=[Address, Uint(256)]),
///   content="transfer(address,uint256)",
/// )
/// ```
pub fn signature(
  name~ : String,
  inputs~ : Array[AbiType],
) -> String raise AbiError {
  // a parameter list is spelled exactly like a tuple
  name + AbiType::Tuple(inputs).name()
}

///|
/// The 4-byte function selector a signature hashes to: the first four bytes of
/// `keccak256` of the signature. It is what calldata starts with, and what the
/// contract dispatches on.
///
/// ```
/// inspect(
///   @abi.selector("transfer(address,uint256)"),
///   content="0xa9059cbb",
/// )
/// ```
pub fn selector(signature : String) -> @types.Hex {
  @types.Hex::from_bytes(selector_bytes(signature))
}

///|
/// The four bytes themselves, for the caller that goes on to concatenate them.
fn selector_bytes(signature : String) -> Bytes {
  let hash = @crypto.keccak256_string(signature)
  Bytes::makei(SELECTOR_SIZE, i => hash[i])
}

///|
/// Bytes of `keccak256` that pick a function out of a contract.
const SELECTOR_SIZE = 4

///|
/// The topic an event with this signature is logged under: the whole 32-byte
/// `keccak256`, not the first four bytes.
///
/// It is `topics[0]` of every log the event produces, so it is what a log
/// filter matches on and what tells one event from another when reading a
/// receipt.
///
/// ```
/// inspect(
///   @abi.event_topic("Transfer(address,address,uint256)"),
///   content="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
/// )
/// ```
pub fn event_topic(signature : String) -> @types.Hex {
  @types.Hex::from_bytes(@crypto.keccak256_string(signature))
}

///|
/// Build the calldata for a call: the function's selector followed by its
/// ABI-encoded arguments.
///
/// This is the whole write side of the ABI in one call — what goes into a
/// `CallRequest`'s or a `TransactionRequest`'s `data`.
///
/// ```
/// let data = @abi.encode_call(
///   name="balanceOf",
///   inputs=[Address],
///   args=[Address(@types.Address::from_string("0x000000000000000000000000000000000000dead"))],
/// )
/// inspect(
///   data,
///   content=(
///     "0x70a08231" +
///     "000000000000000000000000000000000000000000000000000000000000dead"
///   ),
/// )
/// ```
pub fn encode_call(
  name~ : String,
  inputs~ : Array[AbiType],
  args~ : Array[AbiValue],
) -> @types.Hex raise AbiError {
  let selector = _digits_of_bytes(selector_bytes(signature(name~, inputs~)))
  @types.Hex::from_bytes(
    _bytes_of_digits(selector + _encode_block(inputs, args)),
  )
}
