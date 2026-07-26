# e2e testing backends

The `Backend` trait in `backend.mbt` is what an end-to-end run needs in place
before the SDK can reach a real node — an endpoint, and whatever environment
setup that endpoint implies — plus `run`, the protocol every backend shares:
skip when unconfigured, install once, run the body in a task group.

| Package         | Node        | Environment it installs                         |
| --------------- | ----------- | ----------------------------------------------- |
| `backend/anvil` | local Anvil | a fake EIP-1193 wallet at `globalThis.ethereum` |

Adding one means implementing three methods (`name`, `endpoint`, `install`) and
an `on` that hands the test body a `Provider`. An HTTP transport
([#19](https://github.com/poteto0/endor.mbt/issues/19)) would install nothing
at all — which is the reason the trait exists rather than the setup living in
the tests.

Nothing here ships: `moon.mod` excludes `backend` from the published archive
and `just release-check` asserts it. `backend/anvil` overwrites
`globalThis.ethereum`, which a wallet SDK must never hand a consumer.

What the Anvil backend does and does not prove is in
[`docs/e2e.md`](../docs/e2e.md).
