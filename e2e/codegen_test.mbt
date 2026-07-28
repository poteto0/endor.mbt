///|
/// What `abi/codegen` produces from `fixtures/abi/erc20.abi`, checked against a
/// real EVM rather than against a string.
///
/// The unit tests in `abi/codegen` compare generated source to expected source.
/// That catches a template that changed shape; it cannot catch the mistake that
/// actually costs money, which is a *correct-looking* preset that dispatches to
/// the wrong function — a signature assembled with a parameter type subtly
/// wrong (`uint256` where the contract said `uint128`, a `uint` alias not
/// expanded) hashes to a selector no contract answers, and reads back as
/// garbage or reverts. Nothing about the source text says so.
///
/// So the fixture is taken end to end: read off disk, run through the
/// generator, and the signatures it says the generated file covers are hashed
/// into selectors and deployed as `@anvil.deploy_selector_gate` contracts — a
/// contract that answers `42` for exactly those four bytes and reverts for any
/// other. The hand-written `@erc20.Erc20`, whose calls the generator is
/// supposed to reproduce, is then pointed at each gate. It answers only if both
/// halves agreed on the function, on a real EVM, over the real wire.

///|
/// Read a file from the repository.
///
/// The e2e suite already declares `extern "js"` to stand in for the environment
/// *underneath* the SDK (`backend/anvil/js.mbt` fabricates a wallet); this is
/// the same licence used for something much smaller. It binds no wallet
/// functionality and ships nowhere: `e2e/` is excluded from the archive.
extern "js" fn read_file(path : String) -> String =
  #| (path) => require('node:fs').readFileSync(path, 'utf8')

///|
/// `moon test` runs from the module root, so this is the fixture the CLI is
/// pointed at in `just codegen-check` — the same bytes, not a copy.
const ERC20_FIXTURE = "fixtures/abi/erc20.abi"

///|
/// The generated preset has to cover the interface the hand-written one does.
///
/// This is the claim the live tests below then check the *meaning* of: here it
/// is only that nothing was quietly skipped. A generator that declined every
/// member would pass every selector test underneath, because it would deploy no
/// gates at all.
async test "the fixture generates every member the hand-written preset has" {
  @anvil.on(_ => {
    let out = @codegen.generate("Erc20", read_file(ERC20_FIXTURE))
    assert_eq(out.skipped.join("\n"), "")
    for
      signature in [
        "name()", "symbol()", "decimals()", "totalSupply()", "balanceOf(address)",
        "allowance(address,address)", "transfer(address,uint256)", "approve(address,uint256)",
        "transferFrom(address,address,uint256)", "Transfer(address,address,uint256)",
        "Approval(address,address,uint256)",
      ] {
      assert_true(out.members.contains(signature))
    }
  })
}

///|
/// Every reading getter, dispatched for real.
///
/// The gate is deployed for the selector the *fixture* yields, and called
/// through the *hand-written* preset. A `42` back means the two agreed on all
/// four bytes; a revert would mean the generator built a signature the preset
/// does not send, which is exactly the bug no amount of comparing source text
/// finds.
async test "a getter the fixture describes is the getter the preset calls" {
  @anvil.on(provider => {
    let members = @codegen.generate("Erc20", read_file(ERC20_FIXTURE)).members
    for
      probe in [
        ("totalSupply()", (t : @erc20.Erc20) => t.total_supply(provider)),
        (
          "balanceOf(address)",
          t => t.balance_of(provider, @anvil.dev_account()),
        ),
        (
          "allowance(address,address)",
          t => {
            t.allowance(
              provider,
              owner=@anvil.dev_account(),
              spender=@anvil.other_account(),
            )
          },
        ),
      ] {
      // the signature comes out of the fixture, not out of this file
      assert_true(members.contains(probe.0))
      let gate = @anvil.deploy_selector_gate(provider, @abi.selector(probe.0))
      assert_eq((probe.1)(@erc20.Erc20::new(gate)), 42N)
    }
  })
}

///|
/// `decimals()` is `uint8`, and the fixture says so. A generator that widened
/// every integer to `uint256` would still produce the same *selector* here — a
/// return type is not part of a signature — so what this pins is the other
/// half: that the width the fixture declared survives into what the preset
/// decodes the answer as.
async test "the width the fixture declares is the width that is decoded" {
  @anvil.on(provider => {
    let out = @codegen.generate("Erc20", read_file(ERC20_FIXTURE))
    assert_true(out.code.contains("name=\"decimals\", outputs=[Uint(8)])"))
    let gate = @anvil.deploy_selector_gate(
      provider,
      @abi.selector("decimals()"),
    )
    inspect(@erc20.Erc20::new(gate).decimals(provider), content="42")
  })
}

///|
/// The negative control, without which none of the above proves anything.
///
/// A gate deployed for one selector must refuse another. If it answered
/// regardless — as `@anvil.deploy_answer_contract` does — every test here would
/// pass no matter what signature the generator invented.
async test "a gate deployed for another selector refuses the call" {
  @anvil.on(provider => {
    // `totalSupply()` reaching a gate built for `balanceOf(address)`
    let gate = @anvil.deploy_selector_gate(
      provider,
      @abi.selector("balanceOf(address)"),
    )
    try @erc20.Erc20::new(gate).total_supply(provider) |> ignore catch {
      _ => ()
    } noraise {
      _ => fail("the gate answered a selector it was not deployed for")
    }
  })
}

///|
/// A write, dispatched for real: the gate accepts the transaction only if the
/// four bytes match, so a mined receipt is the same proof for `send` that a
/// decoded `42` is for `call`.
async test "a state-changing function the fixture describes is the one sent" {
  @anvil.on(provider => {
    let members = @codegen.generate("Erc20", read_file(ERC20_FIXTURE)).members
    assert_true(members.contains("transfer(address,uint256)"))
    let gate = @anvil.deploy_selector_gate(
      provider,
      @abi.selector("transfer(address,uint256)"),
    )
    let hash = @erc20.Erc20::new(gate).transfer(
      provider,
      from=@anvil.dev_account(),
      to=@anvil.other_account(),
      amount=1N,
    )
    let receipt = @provider.wait_for_receipt(
      provider,
      hash,
      timeout=5_000,
      poll_interval=100,
    )
    // a transaction the gate rejected would be mined as `Reverted`
    inspect(receipt.status, content="Success")
  })
}

///|
/// An event's topic is a hash of a signature and nothing else, so a node cannot
/// be asked whether it is right — but the hand-written preset and the fixture
/// can be asked to agree, which is the same claim the selector gates make for
/// functions.
async test "the topic the fixture yields is the topic the preset uses" {
  @anvil.on(_ => {
    let members = @codegen.generate("Erc20", read_file(ERC20_FIXTURE)).members
    assert_true(members.contains("Transfer(address,address,uint256)"))
    assert_eq(
      @abi.event_topic("Transfer(address,address,uint256)"),
      @erc20.Erc20::transfer_topic(),
    )
  })
}
