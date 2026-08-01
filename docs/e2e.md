# Verifying against a real node

Everything under `provider/` is unit-tested against `MockProvider`, which
answers whatever the test told it to. That proves the typed layer decodes what
it is handed; it cannot prove a node accepts what the SDK sends. `e2e/` closes
that gap by running the real `BrowserProvider` against a local
[Anvil](https://getfoundry.sh/anvil/overview) node.

```sh
just anvil     # terminal 1: a throwaway chain on 127.0.0.1:8545
just e2e       # terminal 2: the e2e suite against it
```

CI runs the same thing in a separate `e2e` job (`.github/workflows/ci.yml`).

## How a browser SDK gets tested without a browser

`BrowserProvider` reads `globalThis.ethereum` — an EIP-1193 object with a
`request({ method, params })` method returning a promise. Nothing about it
requires an extension, and the js tests already run in Node, which has `fetch`.

The other half is that **Anvil is itself a wallet**: it starts with ten funded,
*unlocked* dev accounts, so it answers `eth_accounts`, `eth_sendTransaction`
and the signing methods on its own. No key management, no approval UI.

So `backend/anvil/js.mbt` installs a `globalThis.ethereum` that forwards
EIP-1193 requests to Anvil over HTTP JSON-RPC. The SDK, the FFI envelope, the
JSON it emits, and the decoding of what comes back are all the real code paths;
only the transport underneath the injected object differs from a browser.

```
@provider.balance ─▶ BrowserProvider ─▶ ffi/js ─▶ globalThis.ethereum ─▶ HTTP ─▶ anvil
     typed helper       real code       real code      the shim
```

### What is real and what is emulated

Real — answered by Anvil's EVM: every helper in the
[reference](https://endor.poteto-mahiro.com/reference/) — the reads, `call` / `estimate_gas` against a
contract the suite deploys, and `send_transaction`, whose transactions the node
really mines and prices (which is how the suite pins that `Fee::Auto` produces
a type-`0x02` transaction).

Emulated by the shim, because a node has no counterpart: the two `wallet_*`
methods, and one rejection. A node cannot decline on the user's behalf, so a
send from `@anvil.reject_account()` is refused with **4001** instead of being
forwarded — enough to prove the code reaches `UserRejected` through the real FFI
boundary, not that an extension would raise it. `wallet_switchEthereumChain` succeeds for the chain the node is
already on (or one previously added) and raises **4902** otherwise;
`wallet_addEthereumChain` records the chain and succeeds. That is enough to
exercise `switch_or_add_chain`'s fallback wiring, but the node keeps serving
its own chain either way — no real network switch happens.

Not covered at all: the approval UI. Nothing here proves MetaMask renders a
sane confirmation, or that a user rejection surfaces as `UserRejected` from a
real extension. That is what the manual checklist below is for.

## The suite

Three packages of the root module, so they build against the working tree
rather than the published release:

- `backend/` — the `Backend` trait (`name` / `endpoint` / `install`) and `run`,
  the skip-install-task-group protocol. No FFI, no `js`.
- `backend/anvil/` — the Anvil implementation: the shim, the dev accounts, the
  test contract. `@anvil.on(provider => …)` is what a test calls.
- `e2e/` — the test cases, and nothing else.

`backend/` and `e2e/` never ship. `moon.mod` excludes both and
`just release-check` asserts it before a tag exists — a mooncakes release
cannot be taken back, and a wallet SDK that hands consumers a function
overwriting `globalThis.ethereum` would be a real footgun.

`e2e/codegen_test.mbt` is also the one place that reads a repository file at
run time (`fixtures/`, through a test-only `extern "js"`), which is why it lives
here rather than beside the generator's own unit tests.

`Backend::endpoint` reads `ENDOR_E2E_RPC_URL`, and `run` **skips when it is
unset** — that is why `just ut` needs no node. Two things keep a skip from
passing for a pass: `run` says so once on stdout, and `just e2e` refuses to run
until something answers on the port.

Two contracts are deployed, both hand-written EVM of a few dozen bytes.
Deployment is in each case a `send_transaction` with no `to` followed by a
`wait_for_receipt`, with the address read off the receipt's `contract_address`.

`ANSWER_CONTRACT_CODE` (`@anvil.deploy_answer_contract`) always returns the word
`42`, whatever it is called with. It exists so `call`, `estimate_gas`, `code`
and `is_contract` have real bytecode to talk to without the SDK needing an ABI
layer (#18).

`@anvil.deploy_selector_gate(provider, selector)` is the opposite: it returns
`42` for exactly the four bytes it was deployed for and reverts for everything
else. Ignoring the calldata is what makes the answer contract useless for the
question `e2e/codegen_test.mbt` asks — whether the *experimental* ABI generator
(#48) and the hand-written `@erc20.Erc20` dispatch to the same function. Both
halves are given the gate; only agreement on all four bytes gets an answer, and
a test in that file deploys a gate for the wrong selector to prove the check has
teeth. The fixture it reads, `fixtures/abi/erc20.abi`, is the same file
`just codegen-check` runs the CLI against, so a change to one is caught by the
other.

`fixtures/abi/answer.json` is the second half of the same arrangement: a
compiler *artifact*, so the generator emits a `deploy` from it, and the file
deploys the creation code it embedded — the answer contract's — through
`@contract.deploy` with the constructor arguments the generated file encodes.
Compiling that `deploy` is `just codegen-check`'s job; putting its bytes on a
real chain is this one's, and it is the only check that the hex reached the
generated literal intact.

Tests share one chain and run concurrently, so assertions are about what a
fresh chain guarantees (a nonce *grows*, it does not become exactly `n + 1`),
and the shim is installed once rather than per test. The shim also queues
`eth_sendTransaction`: without that serialization concurrent tests are handed
the same nonce, and a wallet prompting one transaction at a time is what a
browser would do anyway. The signing methods do not need it: they change no
state, so nothing they do depends on the order they run in.

## Manual QA before a release

The automated suite never touches an extension, so a human still walks the
approval path once per release:

1. `just anvil`, then add it to MetaMask as a custom network — RPC URL
   `http://127.0.0.1:8545`, chain id `31337`, symbol `ETH`.
2. Import the first dev account with the private key Anvil prints at startup
   (`0xac09…ff80`), so the account is funded.
3. Run the demo per [`examples/README.md`](../examples/README.md) — it
   documents what each field should show.

Then walk the six paths only an extension can exercise:

4. **Approve** the connect prompt → the card fills in, chain id `31337
   (0x7a69)`, a non-zero balance.
5. **Reject** a connect prompt → the status line shows the rejection; the page
   neither hangs nor throws.
6. **Approve** a chain switch (**Sepolia**) → the card follows to `11155111`
   and re-reads the balance.
7. **Reject** a chain switch → the status line shows it and the card stays on
   the previous chain.
8. **Approve** a send → switch to **Sepolia** or **Polygon Amoy** (a faucet
   funds the account), put another address and `0.001` in the Send row, and
   confirm in the wallet. The **Last tx** field fills in with the hash, and the
   explorer shows it mined.
9. **Reject** the send → the status line says so; nothing is broadcast and
   **Last tx** does not change.

Steps 8 and 9 are the transaction half. The node-side half is already in
`e2e/`, which proves the wire format a node accepts and that 4001 maps to
`UserRejected`; what only the extension can prove is that its confirmation
dialog shows the right recipient and amount. Signing splits the same way: `e2e/`
signs with `personal_sign` and `eth_signTypedData_v4` against Anvil's unlocked
dev accounts, which proves the parameter order and the serialized EIP-712
document a node accepts, while only an extension can show that its prompt
renders the message as text rather than as hex.

### Why no headless wallet

Driving MetaMask headlessly (synpress and friends) means a browser, an
extension build and a seed phrase in CI, and it breaks whenever the extension's
UI moves. For an SDK this size that cost buys only step 4 and 6 above. The
split — Anvil for everything the protocol defines, a short human checklist for
the approval UI — is the deliberate trade.
