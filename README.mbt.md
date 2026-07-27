# endor.mbt

An Ethereum SDK for MoonBit. Currently focused on browser wallets via the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider standard: it wraps
the provider that extensions such as MetaMask inject as `globalThis.ethereum`,
and exposes it as typed, async MoonBit functions.

![demo](https://raw.githubusercontent.com/poteto0/endor.mbt/main/docs/movie/demo.gif)

> See [`docs/scope.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/scope.md)
> for what's wrapped — anything unwrapped is still reachable through
> `Provider::request`.

## Install

```sh
moon add poteto0/endor
```

Then import the packages you need in your `moon.pkg`:

```
import {
  "poteto0/endor/provider",         // @provider — Provider, typed RPC, errors
  "poteto0/endor/provider/browser", // @browser — the injected wallet
  "poteto0/endor/ffi/js",           // @js — spawn (bridge async to the JS event loop)
}
```

The domain types are re-exported from the root package, so
`"poteto0/endor"` gives you `@endor.Address`, `@endor.ChainId`, and friends when
you need to spell a type out.

## Getting a wallet address

```
async fn connect() -> Unit {
  try {
    // raises NotInstalled when no wallet extension is present
    let wallet = @browser.BrowserProvider::require()
    match @provider.request_accounts(wallet).get(0) { // eth_requestAccounts
      Some(addr) => println("address: \{addr}")
      None => println("no authorized accounts")
    }
    let chain = @provider.chain_id(wallet) // eth_chainId
    println("chain: \{chain.to_uint64()} (\{chain.to_hex()})")
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}

fn main {
  @js.spawn(connect) // bridge async to the JS event loop
}
```

A runnable version of this lives in
[`examples/get-address`](https://github.com/poteto0/endor.mbt/tree/main/examples/get-address),
which renders the same values onto a page, together with an `index.html` you can
open in a browser that has a wallet installed — see
[`examples/README.md`](https://github.com/poteto0/endor.mbt/blob/main/examples/README.md)
for the build-and-serve steps.

## Reading a contract

```
async fn total_supply(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
) -> Unit {
  try {
    // `totalSupply()` — a selector with no arguments, until the ABI layer lands
    let req = @endor.CallRequest::new(
      token,
      data=@endor.Hex::from_string("0x18160ddd"),
    )
    let ret = @provider.call(wallet, req) // eth_call
    println("returned \{ret.byte_length()} bytes: \{ret}")
    let gas = @provider.estimate_gas(wallet, req) // eth_estimateGas
    println("would cost \{gas.to_uint64()} gas")
  } catch {
    e => println("error: \{e}")
  }
}
```

`call` evaluates the request against the node's state instead of broadcasting it,
so it needs no signature and never prompts the user; `estimate_gas` simulates the
same request and answers with the gas it would need. `to` is the only required
field of a `CallRequest` — `from`, `data` and `value` are optional and omitted
from the request when absent. A call that reverts comes back as a `ProviderError`,
which makes `estimate_gas` a cheap pre-flight check before asking anyone to sign.

## Sending a transaction

```
async fn tip(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  to : @endor.Address,
) -> Unit {
  try {
    let hash = @provider.send_transaction(
      wallet,
      @endor.TransactionRequest::new(from, to~, value=@endor.Wei::from_int(1000)),
    ) // eth_sendTransaction
    println("broadcast as \{hash}")
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

This is the first call that spends the user's money, so it is the first that
always prompts: `from` is required — it is the account that signs — and a user
who declines comes back as `UserRejected`. Everything the request leaves out
(`nonce`, `gas`, the fees) the wallet fills in, and leaving `to` out is how a
transaction _deploys_ the contract in `data`.

The fees are a `Fee` rather than three optional fields, because `gasPrice` and
the EIP-1559 pair are mutually exclusive on the wire — geth rejects a request
carrying both. The default, `Auto`, sends no fee field at all: since London that
means the node builds an EIP-1559 (type `0x02`) transaction, and `Legacy` is how
you opt out of that on a chain that never forked.

The `TxHash` you get back says the transaction was _broadcast_, not mined —
waiting for a receipt is [#11](https://github.com/poteto0/endor.mbt/issues/11).

## Switching chains

```
async fn to_polygon(wallet : @browser.BrowserProvider) -> Unit {
  try {
    @provider.switch_or_add_chain(
      wallet,
      @endor.ChainParams::new(
        @endor.ChainId::polygon(),
        chain_name="Polygon Mainnet",
        rpc_urls=["https://polygon-rpc.com"],
        native_currency=@endor.NativeCurrency::new(name="POL", symbol="POL"),
      ),
    )
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

`switch_or_add_chain` sends `wallet_switchEthereumChain`, and when the wallet
answers 4902 — it does not know that chain — adds it with
`wallet_addEthereumChain` from the same `ChainParams` and switches again. That
fallback is the part every dapp otherwise writes by hand; `switch_chain` and
`add_chain` are the individual steps when you want them.

## Scope

The reads are wrapped in typed helpers: accounts (`eth_requestAccounts`,
`eth_accounts`), the current chain (`eth_chainId`), and the account and chain
state behind `eth_getBalance`, `eth_blockNumber`, `eth_getTransactionCount`,
`eth_gasPrice` and `eth_getCode`. On top of those, `call` / `estimate_gas`
evaluate a request without broadcasting it, `send_transaction` broadcasts one,
and `switch_chain` / `add_chain` / `switch_or_add_chain` move the wallet between
chains. Blocks and receipts, signing, and provider events are planned but not
implemented; until they land, `Provider::request` reaches any method with raw
`Json`.

**→ [`docs/scope.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/scope.md)**
for the full list, what each helper returns, and how to use the escape hatch.
**→ [`docs/roadmap.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/roadmap.md)**
for where the unimplemented parts sit in the plan.

## Layout

| Package                  | Contents                                                                                                    |
| ------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `endor` (root)           | re-exports the domain types, so they can be spelled `@endor.Address`                                        |
| `endor/types`            | `Address`, `Hex`, `ChainId`, `Wei`, `Quantity`, `BlockTag`, `CallRequest`, `ChainParams` and their codecs   |
| `endor/crypto`           | `keccak256` — the hash Ethereum builds its identifiers from; a leaf package, depending on nothing else here |
| `endor/provider`         | `Provider` trait, `ProviderError`, typed RPC helpers, `MockProvider`                                        |
| `endor/provider/browser` | `BrowserProvider` — the injected `globalThis.ethereum`, wrapped                                             |
| `endor/ffi/js`           | the only `extern "js"` code: `globalThis.ethereum` access, `request`, `spawn`                               |

`endor`, `endor/crypto`, `endor/types` and `endor/provider` are backend-agnostic;
`endor/ffi/js` and therefore `endor/provider/browser` are `js`-only, since the
whole point there is a browser-injected object.

Wallet-side failures never panic: EIP-1193 / EIP-1474 codes map onto
`ProviderError` variants (`UserRejected`, `UnrecognizedChain`, …), and the SDK's
own internal failures use `ProviderError::internal`.

## Development

From a clone of the [repository](https://github.com/poteto0/endor.mbt) — the
recipes below live in its `justfile`, which is not part of the published package.
The default target is `js`, since the SDK drives a browser-injected object.

```sh
just ut     # unit tests — no browser or wallet needed
just build  # build for js, including the example
just ci     # test, format, check, and refresh generated interfaces
```

The typed RPC layer is tested against `MockProvider`, so nothing in the test
suite requires a wallet.
