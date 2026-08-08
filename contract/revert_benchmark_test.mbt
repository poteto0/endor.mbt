///|
/// The ERC-6093 declarations an ERC-20 is read against — `@erc20`'s own list,
/// written out here because `contract` is below `contract/erc20`. Six is what a
/// real token carries, and a revert is matched against them one at a time.
fn bench_errors() -> Array[@contract.ErrorDef] {
  [
    { name: "ERC20InvalidSender", inputs: [Address] },
    { name: "ERC20InvalidReceiver", inputs: [Address] },
    { name: "ERC20InvalidApprover", inputs: [Address] },
    { name: "ERC20InvalidSpender", inputs: [Address] },
    {
      name: "ERC20InsufficientBalance",
      inputs: [Address, Uint(256), Uint(256)],
    },
    {
      name: "ERC20InsufficientAllowance",
      inputs: [Address, Uint(256), Uint(256)],
    },
  ]
}

///|
/// A revert of the *last* declaration in a list, so matching it walks all of
/// them. Encoded from that declaration rather than written out, so a rename
/// cannot leave the bench measuring a miss through all six instead.
fn bench_reverted_last(
  errors : Array[@contract.ErrorDef],
) -> @provider.ProviderError {
  let def = errors[errors.length() - 1]
  reverted(
    revert_data(def.name, def.inputs, [
      Address(test_address()),
      Uint(1N),
      Uint(2N),
    ]),
  )
}

///|
/// `count` reverts read against the same declarations, the way a batch of
/// failed sub-calls is read. A revert that does not decode as the custom error
/// aborts rather than being counted as a fast iteration.
fn read_reverts(
  count : Int,
  error : @provider.ProviderError,
  errors : Array[@contract.ErrorDef],
) -> Unit {
  for _ in 0..<count {
    guard @contract.revert_error(error, errors~)
      is CustomError(name=Some(_), ..) else {
      abort("revert_error: no declaration matched")
    }
  }
}

///|
/// Reading a revert, one and a batch of them, against six declarations.
///
/// The `Error(string)` row matches a written-out constant and looks at no
/// declaration. The gap to the rows below holds more than the declaration walk —
/// the payloads differ too — but the walk is what x500 multiplies.
test "bench: revert_error" (b : @bench.T) {
  let errors = bench_errors()
  let custom = bench_reverted_last(errors)
  let string_revert = reverted(revert_data("Error", [String], [String("nope")]))
  b.bench(name="Error(string)", fn() {
    ignore(@contract.revert_error(string_revert))
  })
  b.bench(name="ERC20InsufficientAllowance", fn() {
    read_reverts(1, custom, errors)
  })
  b.bench(name="ERC20InsufficientAllowance x500", fn() {
    read_reverts(500, custom, errors)
  })
}
