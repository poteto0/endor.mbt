///|
/// The [Multicall3](https://github.com/mds1/multicall) contract: several
/// contract reads bundled into a single `eth_call`.
///
/// One read per RPC round trip is what a contract layer costs by default, and
/// listing anything — a token's `name`, `symbol`, `decimals` and then a
/// `balanceOf` per holder — turns that into an n+1 the caller pays for in
/// latency. `aggregate3` is the chain's own answer to it: the calls are handed
/// to a contract that makes them, so the node executes all of them against the
/// same block and answers once.
///
/// The address is the same on every major chain, which is why `new` takes none;
/// a chain where it is not deployed is what `is_deployed` is for, and passing an
/// address is what a private deployment is for.
///
/// ```
/// async fn[P : @provider.Provider] two_reads(
///   p : P,
///   token : @endor.Address,
/// ) -> Array[@multicall.Outcome] raise @contract.ContractError {
///   let erc20 = @contract.Contract::new(token)
///   @multicall.Multicall3::new().aggregate3(p, [
///     @multicall.Call::new(erc20.prepare(name="symbol", outputs=[String])),
///     @multicall.Call::new(erc20.prepare(name="decimals", outputs=[Uint(8)])),
///   ])
/// }
/// ```
pub struct Multicall3 {
  priv at : @types.Address
} derive(Eq, @debug.Debug)

///|
/// The address Multicall3 is deployed at on every major chain —
/// `0xcA11bde05977b3631167028862bE2a173976CA11`. It is the same everywhere
/// because it was deployed from the same key with the same nonce, which is what
/// lets `new` default to it rather than take a per-chain table.
///
/// ```mbt check
/// test "doc: the canonical address" {
///   inspect(
///     @multicall.default_address().to_checksum_string(),
///     content="0xcA11bde05977b3631167028862bE2a173976CA11",
///   )
/// }
/// ```
pub fn default_address() -> @types.Address {
  canonical
}

///|
/// Parsed once rather than on every `new`: the literal is checksummed, so
/// reading it is a `keccak256` over its digits, and it answers the same address
/// every time. `codec`'s digit table and `crypto`'s round constants are hoisted
/// for the same reason.
///
/// The `abort` is unreachable and the doc test on `default_address` is what says
/// so — it asserts the literal reads back as itself.
let canonical : @types.Address = @types.Address::from_string(
  "0xcA11bde05977b3631167028862bE2a173976CA11",
) catch {
  _ => abort("the canonical Multicall3 address is not an address")
}

///|
/// Point at a Multicall3 deployment, the canonical one unless another is given.
///
/// An address is worth passing on a chain that has its own deployment, or in a
/// test against a node where the contract was deployed by the test itself.
pub fn Multicall3::new(address? : @types.Address) -> Multicall3 {
  Multicall3::{ at: address.unwrap_or(default_address()) }
}

///|
/// The address the batch call goes to.
pub fn Multicall3::address(self : Multicall3) -> @types.Address {
  self.at
}

///|
/// Whether there is a contract at that address at all.
///
/// The canonical deployment is on every major chain but not on *every* chain,
/// and a batch sent to an address holding no code answers with empty return
/// data rather than with an error — which reads as a decode failure and says
/// nothing about the cause. Asking first is one `eth_getCode`, and a caller
/// that finds `false` falls back to calling one at a time.
///
/// ```
/// async fn[P : @provider.Provider] batchable(
///   p : P,
/// ) -> Bool raise @contract.ContractError {
///   @multicall.Multicall3::new().is_deployed(p)
/// }
/// ```
pub async fn[P : @provider.Provider] Multicall3::is_deployed(
  self : Multicall3,
  provider : P,
  block? : @types.BlockTag,
) -> Bool raise @contract.ContractError {
  // `eth_getCode` is not `eth_call` and cannot come back reverted, so there is
  // nothing here for `revert_error` to decode — this failure is the node's
  @provider.is_contract(provider, self.at, block?) catch {
    e => raise @contract.ContractError::Rpc(e)
  }
}

///|
/// One element of a batch: a prepared call, and whether the whole batch may
/// survive its failure.
///
/// `allow_failure` defaults to `true`, which is the reason to bundle reads in
/// the first place — nineteen balances should not be lost because the twentieth
/// address is not a token. Set it to `false` for a call whose failure makes the
/// rest meaningless: `aggregate3` then reverts, and the batch raises.
///
/// ```mbt check
/// test "doc: one element of a batch" {
///   let at = @types.Address::from_string(
///     "0x52908400098527886E0F7030069857D2E4169EE7",
///   )
///   let prepared = @contract.Contract::new(at).prepare(name="decimals", outputs=[
///     Uint(8),
///   ])
///   let batch = [@multicall.Call::new(prepared, allow_failure=false)]
///   inspect(batch.length(), content="1")
/// }
/// ```
pub struct Call {
  priv prepared : @contract.PreparedCall
  priv allow_failure : Bool
} derive(Eq, @debug.Debug)

///|
/// Put a prepared call into a batch.
pub fn Call::new(
  prepared : @contract.PreparedCall,
  allow_failure? : Bool = true,
) -> Call {
  Call::{ prepared, allow_failure }
}

///|
/// What one call of a batch answered.
///
/// It is `pub(all)` for the reason every answer read off the wire is: the SDK
/// builds these from the `(success, returnData)` pairs the contract returned
/// and the caller matches on them. A failure is a *value* here rather than
/// something raised, because the point of the batch is that the other elements
/// still have answers.
pub(all) enum Outcome {
  /// The call succeeded and its return data decoded as the `outputs` the
  /// prepared call declared.
  Returned(Array[@types.AbiValue])
  /// The call did not answer usably: it reverted — decoded the way any revert
  /// is, so `Revert` / `Panic` / `CustomError` all arrive here — or it
  /// succeeded and its return data could not be read as the declared types
  /// (`Abi`).
  Failed(@contract.ContractError)
} derive(Eq)

///|
pub impl Show for Outcome with fn output(self, logger) {
  match self {
    Returned(values) =>
      logger.write_string(
        "Returned(\{values.map(v => v.to_string()).join(", ")})",
      )
    Failed(e) => logger.write_string("Failed(\{e})")
  }
}

///|
/// The values, or the failure raised.
///
/// The accessor for "I expected this one to work": a batch is often several
/// reads that are only interesting together, and matching each `Outcome` to
/// re-raise its error by hand is the same three lines per element.
///
/// ```mbt check
/// test "doc: the values a call answered" {
///   let outcome : @multicall.Outcome = Returned([Uint(1000N)])
///   inspect(outcome.values()[0], content="Uint(1000)")
/// }
/// ```
pub fn Outcome::values(
  self : Outcome,
) -> Array[@types.AbiValue] raise @contract.ContractError {
  match self {
    Returned(values) => values
    Failed(e) => raise e
  }
}

///|
/// `Call3[]` — what `aggregate3` takes: `(address target, bool allowFailure,
/// bytes callData)` per element.
fn call3_array() -> @types.AbiType {
  Array(Tuple([Address, Bool, Bytes]))
}

///|
/// `Result[]` — what it answers with: `(bool success, bytes returnData)` per
/// element, in the order the calls were given.
fn result_array() -> @types.AbiType {
  Array(Tuple([Bool, Bytes]))
}

///|
/// Make every call in one `eth_call` and answer with what each of them said, in
/// the order they were given.
///
/// This is the whole point: one round trip, and every call evaluated against
/// the same block, which a caller looping over `Contract::call` gets neither
/// of. An empty batch answers an empty array without asking the node anything.
///
/// A single call failing is not a failure of the batch — it comes back as
/// `Failed`, carrying the revert decoded against that call's own `ErrorDef`s,
/// and so does a call that succeeded but whose return data does not fit the
/// types it declared. What *does* raise is the batch failing as a whole: the
/// node refusing it, or `aggregate3` itself reverting because an element with
/// `allow_failure = false` failed.
///
/// ```
/// async fn[P : @provider.Provider] symbols(
///   p : P,
///   tokens : Array[@endor.Address],
/// ) -> Array[@multicall.Outcome] raise @contract.ContractError {
///   let calls = []
///   for token in tokens {
///     let erc20 = @contract.Contract::new(token)
///     calls.push(@multicall.Call::new(erc20.prepare(name="symbol", outputs=[String])))
///   }
///   @multicall.Multicall3::new().aggregate3(p, calls)
/// }
/// ```
pub async fn[P : @provider.Provider] Multicall3::aggregate3(
  self : Multicall3,
  provider : P,
  calls : Array[Call],
  from? : @types.Address,
  block? : @types.BlockTag,
) -> Array[Outcome] raise @contract.ContractError {
  // nothing to ask about: an empty batch is an empty answer, and a round trip
  // that returns an empty array is a round trip nobody needed
  guard !calls.is_empty() else { return [] }
  let elements = calls.map(call => {
    @types.AbiValue::Tuple([
      Address(call.prepared.target()),
      Bool(call.allow_failure),
      Bytes(call.prepared.data().to_bytes()),
    ])
  })
  let data = @abi.encode_call(name="aggregate3", inputs=[call3_array()], args=[
    Array(elements),
  ]) catch {
    e => raise @contract.ContractError::Abi(e)
  }
  let request = @types.CallRequest::new(self.at, from?, data~)
  // the batch as a whole: a node that refused, or `aggregate3` reverting
  // because an element that was not allowed to fail did
  let answer = @provider.call(provider, request, block?) catch {
    e => raise @contract.revert_error(e)
  }
  let decoded = @abi.decode([result_array()], answer) catch {
    e => raise @contract.ContractError::Abi(e)
  }
  guard decoded is [Array(results)] else {
    raise @contract.ContractError::Abi(
      InvalidData("aggregate3 did not answer with Result[]"),
    )
  }
  // a count that does not match cannot be lined up with the calls at all, so
  // this one is the batch's failure rather than any element's
  guard results.length() == calls.length() else {
    raise @contract.ContractError::Abi(
      InvalidData(
        "aggregate3 answered with \{results.length()} results for \{calls.length()} calls",
      ),
    )
  }
  results.mapi((i, result) => outcome(calls[i], result))
}

///|
/// Read one `Result` — `(bool success, bytes returnData)` — as what that call
/// answered.
///
/// Nothing here raises: every way one element can be unreadable is that
/// element's `Failed`, because throwing the batch away over one bad answer
/// would undo the reason it was batched.
fn outcome(call : Call, result : @types.AbiValue) -> Outcome {
  guard result is Tuple([Bool(success), Bytes(return_data)]) else {
    return Failed(Abi(InvalidData("aggregate3 element is not (bool, bytes)")))
  }
  let return_data = @types.Hex::from_bytes(return_data)
  guard success else { return Failed(call.prepared.revert(return_data)) }
  Returned(call.prepared.decode(return_data) catch { e => return Failed(e) })
}
