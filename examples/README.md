# endor.mbt examples

## get-address

A minimal browser dapp that detects MetaMask, connects the wallet, and shows the
provider name, connected address, and current chain id **on the page**. It
exercises the typed RPC path:

```
@provider.BrowserProvider::require  ->  @provider.request_accounts  ->  @provider.chain_id
```

The UI is rendered from MoonBit with [luna.mbt](https://github.com/mizchi/luna.mbt):
each field is a signal, the connect flow just assigns domain values to it, and
Luna updates the DOM. `index.html` contributes only a `#app` root and the CSS.

### A separate module

The example is its own MoonBit module (`examples/get-address/moon.mod`) so that
the SDK's own `moon.mod` stays free of UI dependencies. The repository root
carries a `moon.work` listing both members, which is what resolves
`poteto0/endor` to this checkout instead of the registry.

That also means the build artifact lands under the example's module name:

```
_build/js/debug/build/poteto0/endor-examples-get-address/endor-examples-get-address.js
```

### Run

From the repository root:

```sh
just example        # or: just ex
```

Then open <http://localhost:8000/> in a browser that has the MetaMask extension
installed and click **Connect wallet**. The card fills in with:

- **Provider** — `MetaMask`, or `EIP-1193 provider` for other injected wallets
- **Address** — the selected account
- **Chain id** — decimal and hex, e.g. `1 (0x1)`

Failures land in the same card's status line: no extension, a rejected request,
or any other `ProviderError` replaces the status text instead of throwing.

### Notes

- `just example` runs `moon build --target js`, copies the self-contained bundle
  next to `index.html` as `main.js` (which the page loads by relative path), and
  serves that directory. Both steps matter: without the copy the page 404s on
  the script, and MetaMask does not inject `window.ethereum` into `file://`
  pages, so opening `index.html` directly never finds a provider.
- Wallets tie `eth_requestAccounts` to a user gesture, so the flow starts from
  the button's click handler rather than on page load.
