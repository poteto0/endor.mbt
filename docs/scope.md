# Scope

What `poteto0/endor` covers. It reads accounts, balances and the current chain,
evaluates calls without broadcasting them, sends transactions, switches the
wallet between chains through the `wallet_*` methods below, and subscribes to the
provider events that say those answers went stale. It does not yet wait for a
receipt, and it does not sign messages.

The SDK is **stateless**: it caches no current account and no current chain.
Every value comes from the wallet at the moment it is asked for, and events are
delivered to callbacks and nowhere else.

## Wrapped in typed helpers

### Reads

| Function                              | JSON-RPC method           | Returns                 |
| ------------------------------------- | ------------------------- | ----------------------- |
| `@provider.request_accounts(p)`       | `eth_requestAccounts`     | `Array[@endor.Address]` |
| `@provider.accounts(p)`               | `eth_accounts`            | `Array[@endor.Address]` |
| `@provider.chain_id(p)`               | `eth_chainId`             | `@endor.ChainId`        |
| `@provider.balance(p, who)`           | `eth_getBalance`          | `@endor.Wei`            |
| `@provider.block_number(p)`           | `eth_blockNumber`         | `UInt64`                |
| `@provider.transaction_count(p, who)` | `eth_getTransactionCount` | `UInt64` (nonce)        |
| `@provider.gas_price(p)`              | `eth_gasPrice`            | `@endor.Wei`            |
| `@provider.code(p, who)`              | `eth_getCode`             | `@endor.Hex`            |
| `@provider.is_contract(p, who)`       | `eth_getCode`             | `Bool`                  |

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

`call` takes the same `block=`; `estimate_gas` does not, since an estimate is
only meaningful against current state.

### Calls and gas estimation

| Function                         | JSON-RPC method   | Returns           |
| -------------------------------- | ----------------- | ----------------- |
| `@provider.call(p, req)`         | `eth_call`        | `@endor.Hex`      |
| `@provider.estimate_gas(p, req)` | `eth_estimateGas` | `@endor.Quantity` |

Both take an `@endor.CallRequest` — the transaction-shaped object the node
evaluates against its state instead of broadcasting. Neither needs a signature,
so neither prompts the user:

```
let req = @endor.CallRequest::new(
  token,                                        // to (required)
  data=@endor.Hex::from_string("0x70a08231"),   // raw calldata
)
let ret = @provider.call(wallet, req)           // return data, as Hex
let gas = @provider.estimate_gas(wallet, req).to_uint64()
```

`from` (what the callee sees as `msg.sender`) and `value` are optional too, and
what the caller leaves out stays out of the request rather than being sent as
`null`.

There is no ABI layer yet ([#18](https://github.com/poteto0/endor.mbt/issues/18)),
so `data` is calldata the caller encodes and the answer is return data the caller
decodes — a selector plus ABI-encoded arguments in, raw bytes out.

A call the node cannot execute — a revert — is answered as an error, so it
arrives as a `ProviderError` (typically `Rpc(code=3, …)`) rather than as an empty
answer. That is what makes `estimate_gas` a cheap pre-flight check before asking
the user to sign anything. The estimate itself is measured against current state,
so treat it as an upper bound rather than a guarantee.

### Sending transactions

| Function                             | JSON-RPC method       | Returns         |
| ------------------------------------ | --------------------- | --------------- |
| `@provider.send_transaction(p, req)` | `eth_sendTransaction` | `@endor.TxHash` |

It takes an `@endor.TransactionRequest` — the same transaction shape as a
`CallRequest`, except that this one is signed and broadcast, so it always
prompts the user and raises `UserRejected` (4001) when they decline. `from` is
required and comes first: it is the account that signs. Everything else is
optional and stays out of the request when absent, which is how the wallet is
told to work it out itself.

```
let hash = @provider.send_transaction(
  wallet,
  @endor.TransactionRequest::new(
    from,                                 // the signer (required)
    to~,                                  // absent ⇒ deploy `data`
    value=@endor.Wei::from_int(1000),     // wei to send
    // data=, gas=, nonce=, fee= are optional too
  ),
)
```

The answer is an `@endor.TxHash`: a `Hex` narrowed to exactly 32 bytes, so a
wallet answering with something else is caught here rather than at whichever RPC
is later handed the value. It means the transaction was *broadcast* — it can
still be dropped or replaced, and waiting for it to be mined is
[#11](https://github.com/poteto0/endor.mbt/issues/11).

#### Fees: `Auto`, EIP-1559, or legacy

`fee=` is an `@endor.Fee` rather than three optional fields, because the two fee
markets are mutually exclusive on the wire — geth rejects a request carrying
both `gasPrice` and `maxFeePerGas` / `maxPriorityFeePerGas` — and an enum cannot
spell that combination:

| `Fee`                                                  | On the wire                             |
| ------------------------------------------------------ | --------------------------------------- |
| `Auto` (default)                                       | no fee field; the wallet decides        |
| `Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~)` | `maxFeePerGas`, `maxPriorityFeePerGas`  |
| `Legacy(gas_price~)`                                   | `gasPrice`                              |

`Auto` is what a dapp normally wants. Since London, geth defaults a request with
no fee field to an EIP-1559 (dynamic-fee, type `0x02`) transaction — taking
`maxPriorityFeePerGas` from its own tip oracle and `maxFeePerGas` from
`2 * baseFee + tip` — and only builds a legacy transaction when `gasPrice` is
given. So `Legacy` means "opt out of EIP-1559", for a chain that never forked to
London; it is not the default and should not be reached for by habit.

### Chain switching

| Function                                   | JSON-RPC method              |
| ------------------------------------------ | ---------------------------- |
| `@provider.switch_chain(p, chain_id)`      | `wallet_switchEthereumChain` |
| `@provider.add_chain(p, params)`           | `wallet_addEthereumChain`    |
| `@provider.switch_or_add_chain(p, params)` | both, see below              |

All three prompt the user, so they raise `UserRejected` when the user declines.
`switch_chain` raises `UnrecognizedChain` (4902) when the wallet does not know
the chain, which is what the composite absorbs: it switches, and on 4902 adds
the chain and switches again. Any other error propagates from the step that
raised it.

```
@provider.switch_chain(wallet, @endor.ChainId::mainnet())

let polygon = @endor.ChainParams::new(
  @endor.ChainId::polygon(),
  chain_name="Polygon Mainnet",
  rpc_urls=["https://polygon-rpc.com"],
  native_currency=@endor.NativeCurrency::new(name="POL", symbol="POL"),
  block_explorer_urls=["https://polygonscan.com"],
)
@provider.switch_or_add_chain(wallet, polygon)
```

`@endor.ChainParams` is the EIP-3085 description a wallet needs in order to add
a chain it has never seen — a domain type like the rest, so it lives in
`endor/types`. `block_explorer_urls` is optional and left out of the request
when empty; `NativeCurrency`'s `decimals` defaults to 18. Presets such as
`ChainId::mainnet()` / `::polygon()` / `::sepolia()` save spelling the id out.

Adding a chain is also how a wallet switches to it, so `switch_or_add_chain`'s
second switch is redundant on wallets that do both — it is there for the ones
that add without switching.

### Provider events

| Function                                       | EIP-1193 event    | Handler receives         |
| ---------------------------------------------- | ----------------- | ------------------------ |
| `@provider.on_accounts_changed(e, handler)`    | `accountsChanged` | `Array[@endor.Address]`  |
| `@provider.on_chain_changed(e, handler)`       | `chainChanged`    | `@endor.ChainId`         |
| `@provider.on_disconnect(e, handler)`          | `disconnect`      | `@provider.ProviderError` |

All three take an `@provider.EventSource` — a provider that can push, which
`BrowserProvider` and `MockProvider` both are — and return an
`@provider.Subscription`, a plain value with no framework attached whose
`unsubscribe()` stops that one handler and is safe to call twice. The
[README](../README.md#reacting-to-wallet-changes) has the worked example.

`EventSource` is deliberately a **separate trait** from `Provider`: a transport
can answer RPC without being able to push anything back, and the typed RPC
helpers stay usable against one that cannot. Anything the three helpers do not
cover is reachable with the raw `EventSource::subscribe(event~, handler~)`, which
hands the payload over as `Json`.

Because the SDK is stateless, subscribing does not read an initial value:
`on_accounts_changed` fires when the account *changes*, so a dapp reads its
starting point with `@provider.accounts` / `@provider.chain_id` and holds it.
A payload that fails to decode — a `chainChanged` that is not a hex quantity, a
`disconnect` with no numeric `code` — is **dropped**: the handler is not called
and nothing is raised, since an event arrives outside any call the dapp made and
has nowhere to raise to. The subscription stays live and the next well-formed
event is delivered normally.

`accountsChanged` with an empty array is how EIP-1193 says the user revoked the
dapp's permission — it is not `disconnect`, which is the provider losing its
connection to every chain and carries a `ProviderRpcError` (`{code, message}`)
mapped through `ProviderError::from_code`, typically to `Disconnected` (4900).

Not every wallet implements the event API. `@browser.BrowserProvider::has_events()`
reports whether the injected object exposes `on` / `removeListener`; subscribing
to one that does not is inert rather than fatal — the handler simply never fires
and `unsubscribe` is still safe.

Alongside those:

- `@browser.BrowserProvider::detect()` / `::require()` — find
  `globalThis.ethereum`, returning `None` / raising `NotInstalled` when no wallet
  extension is present
- `@browser.BrowserProvider::is_metamask()` — whether the injected provider
  identifies itself as MetaMask
- `@provider.MockProvider` — an in-memory `Provider` for tests, so the RPC layer
  can be exercised without a browser. It is an `EventSource` too:
  `MockProvider::emit(event~, payload~)` fires an event at the subscribed
  handlers, so event handling is testable without a wallet
- `@endor.Address` / `Hex` / `TxHash` / `ChainId` / `Wei` / `Quantity` /
  `BlockTag` / `CallRequest` / `TransactionRequest` / `Fee` / `ChainParams` /
  `NativeCurrency` — domain types with hex and JSON codecs
- `@provider.MockProvider::on_sequence` — canned answers one per call, for
  flows that retry (the 4902 fallback above is tested with it)
- `@provider.ProviderError` — EIP-1193 / EIP-1474 codes mapped onto typed
  variants (`UserRejected`, `UnrecognizedChain`, …). Wallet-side failures never
  panic.

## Planned, not implemented yet

- blocks and receipts (`eth_getBlockByNumber`, `eth_getTransactionReceipt`)
- message signing (`personal_sign`, `eth_signTypedData_v4`)
- EIP-6963 — enumerating several injected providers instead of taking
  `globalThis.ethereum`

## Reaching anything not wrapped

`Provider::request` is the generic escape hatch and takes any method name. It
returns raw `Json` and gives up the typed surface, so prefer the helpers above
wherever they exist:

```
async fn block(
  wallet : @browser.BrowserProvider,
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

The typed RPC layer and the domain types are plain MoonBit. Only the injected
provider itself is JS, so `supported_targets = "js"` is confined to `endor/ffi/js`
and `endor/provider/browser`; the root package, `endor/types` and
`endor/provider` stay backend-agnostic.
