# endor.mbt examples

## get-address

A minimal browser dapp that detects MetaMask, connects the wallet, shows the
provider name, connected address, balance and current chain id **on the page**,
and switches the wallet between chains. It exercises the typed RPC path:

```
@browser.BrowserProvider::require  ->  @provider.request_accounts  ->  @provider.balance / @provider.chain_id
                                   ->  @provider.switch_or_add_chain
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
- **Balance** — the account's balance in wei on the current chain
- **Chain id** — decimal and hex, e.g. `1 (0x1)`

The **Mainnet / Sepolia / Polygon** buttons below the card call
`@provider.switch_or_add_chain`, which switches the wallet and — if the wallet
answers 4902 because it does not know the chain — adds it from the
`ChainParams` in `main.mbt` and switches again. The card re-reads the balance
and chain id afterwards, so the fields follow the wallet.

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
