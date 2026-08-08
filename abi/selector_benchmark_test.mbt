///|
/// `count` calls of the same function, the way a batched read builds them.
///
/// `balanceOf` for many holders is the plainest use of `@multicall`, and every
/// element of that batch names the same function. A call that fails to encode
/// aborts rather than being counted as a fast iteration.
fn encode_calls(count : Int, args : Array[@abi.AbiValue]) -> Unit {
  for _ in 0..<count {
    ignore(@abi.encode_call(name="balanceOf", inputs=[Address], args~)) catch {
      e => abort("encode_call: \{e}")
    }
  }
}

///|
/// The write side of the ABI, one call and a batch of them.
///
/// Both rows measure a signature already hashed once, since the harness repeats
/// the same closure — which is what a batch pays per element. The hash itself is
/// one per process, and `crypto`'s bench is where its price is.
test "bench: encode_call" (b : @bench.T) {
  let args : Array[@abi.AbiValue] = [Address(dead())]
  b.bench(name="balanceOf", fn() { encode_calls(1, args) })
  b.bench(name="balanceOf x500", fn() { encode_calls(500, args) })
}
