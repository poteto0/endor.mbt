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

So `e2e/anvil.mbt` installs a `globalThis.ethereum` that forwards EIP-1193
requests to Anvil over HTTP JSON-RPC. The SDK, the FFI envelope, the JSON it
emits, and the decoding of what comes back are all the real code paths; only
the transport underneath the injected object differs from a browser.

```
@provider.balance ─▶ BrowserProvider ─▶ ffi/js ─▶ globalThis.ethereum ─▶ HTTP ─▶ anvil
     typed helper       real code       real code      the shim
```

### What is real and what is emulated

Real — answered by Anvil's EVM: every helper in
[`docs/scope.md`](./scope.md) (the reads, plus `call` / `estimate_gas` against
a contract the suite deploys), and — once #10 lands — `eth_sendTransaction`
and receipts.

Emulated by the shim, because a node has no counterpart: the two `wallet_*`
methods. `wallet_switchEthereumChain` succeeds for the chain the node is
already on (or one previously added) and raises **4902** otherwise;
`wallet_addEthereumChain` records the chain and succeeds. That is enough to
exercise `switch_or_add_chain`'s fallback wiring, but the node keeps serving
its own chain either way — no real network switch happens.

Not covered at all: the approval UI. Nothing here proves MetaMask renders a
sane confirmation, or that a user rejection surfaces as `UserRejected` from a
real extension. That is what the manual checklist below is for.

## The suite

`e2e/` is a package of the root module, so it builds against the working tree
rather than the published release; it holds only `_test.mbt` files, so it
exports no interface and `moon.mod` keeps it out of the published archive.

Its tests read `ENDOR_E2E_RPC_URL` and **skip when it is unset** — that is why
`just ut` needs no node. Two things keep a skip from passing for a pass: the
suite says so once on stdout, and `just e2e` refuses to run until something
answers on the port.

A contract is deployed from `ANSWER_CONTRACT_CODE`, twenty-odd bytes of hand
written EVM whose runtime always returns the word `42`. It exists so `call`,
`estimate_gas`, `code` and `is_contract` have real bytecode to talk to without
the SDK needing an ABI layer (#18). Deployment goes through
`Provider::request` — the escape hatch for methods not yet typed.

Tests share one chain and run concurrently, so assertions are about what a
fresh chain guarantees (a nonce *grows*, it does not become exactly `n + 1`),
and the shim is installed once rather than per test. The shim also queues
`eth_sendTransaction`: without that serialization concurrent tests are handed
the same nonce, and a wallet prompting one transaction at a time is what a
browser would do anyway. When signing (#14) lands, its methods join the queue
for the same reason.

## Manual QA before a release

The automated suite never touches an extension, so a human still walks the
approval path once per release:

1. `just anvil`, then add it to MetaMask as a custom network — RPC URL
   `http://127.0.0.1:8545`, chain id `31337`, symbol `ETH`.
2. Import the first dev account with the private key Anvil prints at startup
   (`0xac09…ff80`), so the account is funded.
3. Run the demo per [`examples/README.md`](../examples/README.md) — it
   documents what each field should show.

Then walk the four paths only an extension can exercise:

4. **Approve** the connect prompt → the card fills in, chain id `31337
   (0x7a69)`, a non-zero balance.
5. **Reject** a connect prompt → the status line shows the rejection; the page
   neither hangs nor throws.
6. **Approve** a chain switch (**Sepolia**) → the card follows to `11155111`
   and re-reads the balance.
7. **Reject** a chain switch → the status line shows it and the card stays on
   the previous chain.

Once transactions (#10) and signing (#14) land, add "send a transaction to the
second dev account, approve, and see it mined" and "sign a message, approve,
reject once" to this list — and the node-side half of both to `e2e/`.

### Why no headless wallet

Driving MetaMask headlessly (synpress and friends) means a browser, an
extension build and a seed phrase in CI, and it breaks whenever the extension's
UI moves. For an SDK this size that cost buys only step 4 and 6 above. The
split — Anvil for everything the protocol defines, a short human checklist for
the approval UI — is the deliberate trade.
