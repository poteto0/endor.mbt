# Scope

What `poteto0/endor` covers as of **v0.1.0**. The SDK is read-only at this
version: it reads accounts and the current chain, and does not yet write.

## Wrapped in typed helpers

| Function                        | JSON-RPC method       | Returns                     |
| ------------------------------- | --------------------- | --------------------------- |
| `@provider.request_accounts(p)` | `eth_requestAccounts` | `Array[@endor.Address]`     |
| `@provider.accounts(p)`         | `eth_accounts`        | `Array[@endor.Address]`     |
| `@provider.chain_id(p)`         | `eth_chainId`         | `@endor.ChainId`            |

`request_accounts` prompts the wallet to connect if it is not connected yet;
`accounts` never prompts and returns an empty array when the dapp is not
authorized.

Alongside those:

- `@provider.BrowserProvider::detect()` / `::require()` — find
  `globalThis.ethereum`, returning `None` / raising `NotInstalled` when no wallet
  extension is present
- `@provider.BrowserProvider::is_metamask()` — whether the injected provider
  identifies itself as MetaMask
- `@provider.MockProvider` — an in-memory `Provider` for tests, so the RPC layer
  can be exercised without a browser
- `@endor.Address` / `Hex` / `ChainId` / `Wei` — domain types with hex and JSON
  codecs
- `@provider.ProviderError` — EIP-1193 / EIP-1474 codes mapped onto typed
  variants (`UserRejected`, `UnrecognizedChain`, …). Wallet-side failures never
  panic.

## Planned, not implemented yet

- sending transactions (`eth_sendTransaction`)
- message signing (`personal_sign`, `eth_signTypedData_v4`)
- chain switching (`wallet_switchEthereumChain`, `wallet_addEthereumChain`)
- provider events (`accountsChanged`, `chainChanged`, `disconnect`)

## Reaching anything not wrapped

`Provider::request` is the generic escape hatch and takes any method name. It
returns raw `Json` and gives up the typed surface, so prefer the helpers above
wherever they exist:

```
async fn balance(
  wallet : @provider.BrowserProvider,
  who : @endor.Address,
) -> Json raise @provider.ProviderError {
  wallet.request(
    method_name="eth_getBalance",
    params=[who.to_json(), Json::string("latest")],
  )
}
```

Errors still arrive as `ProviderError`: the FFI boundary maps the wallet's error
code through `ProviderError::from_code`, and anything malformed becomes
`ProviderError::internal`.

## Backends

The typed RPC layer and the domain types are plain MoonBit, but the provider it
drives is a browser-injected JS object, so `endor/ffi/js` and `endor/provider`
declare `supported_targets = "js"`. The root package and `endor/types` stay
backend-agnostic.
