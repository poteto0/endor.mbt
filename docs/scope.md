# Scope

What `poteto0/endor` covers as of **v0.1.0**. The SDK is read-only at this
version: it reads accounts, balances and the current chain, and does not yet
write.

## Wrapped in typed helpers

| Function                                | JSON-RPC method           | Returns                 |
| --------------------------------------- | ------------------------- | ----------------------- |
| `@provider.request_accounts(p)`         | `eth_requestAccounts`     | `Array[@endor.Address]` |
| `@provider.accounts(p)`                 | `eth_accounts`            | `Array[@endor.Address]` |
| `@provider.chain_id(p)`                 | `eth_chainId`             | `@endor.ChainId`        |
| `@provider.balance(p, who)`             | `eth_getBalance`          | `@endor.Wei`            |
| `@provider.block_number(p)`             | `eth_blockNumber`         | `UInt64`                |
| `@provider.transaction_count(p, who)`   | `eth_getTransactionCount` | `UInt64` (nonce)        |
| `@provider.gas_price(p)`                | `eth_gasPrice`            | `@endor.Wei`            |
| `@provider.code(p, who)`                | `eth_getCode`             | `@endor.Hex`            |
| `@provider.is_contract(p, who)`         | `eth_getCode`             | `Bool`                  |

`request_accounts` prompts the wallet to connect if it is not connected yet;
`accounts` never prompts and returns an empty array when the dapp is not
authorized.

`is_contract` is `code` with an emptiness test: an externally owned account has
no bytecode.

### Reading at a block

`balance`, `transaction_count`, `code` and `is_contract` all take an optional
`block=`, an `@endor.BlockTag`:

```
@provider.transaction_count(wallet, who, block=Pending)
@provider.balance(wallet, who, block=Number(21962336))
```

The tags are `Latest` (the default), `Pending`, `Earliest`, `Safe`, `Finalized`
and `Number(n)`. `Pending` is the one to use for a nonce, since it counts
transactions the wallet has broadcast but that are not mined yet.

Alongside those:

- `@provider.BrowserProvider::detect()` / `::require()` — find
  `globalThis.ethereum`, returning `None` / raising `NotInstalled` when no wallet
  extension is present
- `@provider.BrowserProvider::is_metamask()` — whether the injected provider
  identifies itself as MetaMask
- `@provider.MockProvider` — an in-memory `Provider` for tests, so the RPC layer
  can be exercised without a browser
- `@endor.Address` / `Hex` / `ChainId` / `Wei` / `Quantity` / `BlockTag` —
  domain types with hex and JSON codecs
- `@provider.ProviderError` — EIP-1193 / EIP-1474 codes mapped onto typed
  variants (`UserRejected`, `UnrecognizedChain`, …). Wallet-side failures never
  panic.

## Planned, not implemented yet

- calls and gas estimation (`eth_call`, `eth_estimateGas`)
- blocks and receipts (`eth_getBlockByNumber`, `eth_getTransactionReceipt`)
- sending transactions (`eth_sendTransaction`)
- message signing (`personal_sign`, `eth_signTypedData_v4`)
- chain switching (`wallet_switchEthereumChain`, `wallet_addEthereumChain`)
- provider events (`accountsChanged`, `chainChanged`, `disconnect`)

## Reaching anything not wrapped

`Provider::request` is the generic escape hatch and takes any method name. It
returns raw `Json` and gives up the typed surface, so prefer the helpers above
wherever they exist:

```
async fn block(
  wallet : @provider.BrowserProvider,
  at : @endor.BlockTag,
) -> Json raise @provider.ProviderError {
  wallet.request(
    method_name="eth_getBlockByNumber",
    params=Json::array([at.to_json(), Json::boolean(false)]),
  )
}
```

Errors still arrive as `ProviderError`: the FFI boundary maps the wallet's error
code through `ProviderError::from_code`, and anything malformed becomes
`ProviderError::internal`.

The raw `Json` it returns can be decoded with the same codecs the helpers use —
`@endor.Quantity::from_json` for any `0x` quantity (block numbers, nonces, gas),
`@endor.Wei::from_json` for wei-denominated ones, and `@endor.Address` /
`@endor.Hex` for the rest.

## Backends

The typed RPC layer and the domain types are plain MoonBit, but the provider it
drives is a browser-injected JS object, so `endor/ffi/js` and `endor/provider`
declare `supported_targets = "js"`. The root package and `endor/types` stay
backend-agnostic.
