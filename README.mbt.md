# endor.mbt

[![docs](https://img.shields.io/badge/docs-endor.poteto--mahiro.com-1f6feb)](https://endor.poteto-mahiro.com)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-poteto0%2Fendor-blue)](https://mooncakes.io/docs/poteto0/endor)
[![CI](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/poteto0/endor.mbt/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/poteto0/endor.mbt/blob/main/LICENSE)

An Ethereum SDK for MoonBit. Currently focused on browser wallets via the
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) provider standard: it wraps
the provider that extensions such as MetaMask inject as `globalThis.ethereum`,
and exposes it as typed, async MoonBit functions.

![demo](https://raw.githubusercontent.com/poteto0/endor.mbt/main/docs/movie/demo.gif)

> **[endor.poteto-mahiro.com](https://endor.poteto-mahiro.com)** is the
> documentation: a cookbook whose every recipe carries a demo you can drive
> against your own wallet, and a reference for what is wrapped — anything
> unwrapped is still reachable through `Provider::request`.

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

### The command-line tools

`endor-cli` is a separate module and a separate install — a binary rather than a
dependency, so nothing it needs ends up in your module's resolution:

```sh
moon install poteto0/endor-cli/endor-cli
```

It generates MoonBit contract presets from JSON ABI documents
(`endor-cli init`, then `endor-cli abi`). Point it at a compiler *artifact* —
`solc --combined-json abi,bin`, a Foundry or Hardhat one — and the preset gets a
`deploy` too, with the creation code embedded. **Experimental**, and not
required to use the SDK — [`cmd/README.md`](cmd/README.md) has the details.

## Getting a wallet address

```mbt-example no-check
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

## Calling a contract

```mbt-example
async fn holdings(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
  who : @endor.Address,
) -> Unit {
  try {
    let token = @erc20.Erc20::new(token)
    // four eth_calls, no prompt and no gas: reads cost the user nothing
    let decimals = token.decimals(wallet)
    let amount = token.balance_of(wallet, who)
    println("\{who} holds \{amount} of \{token.name(wallet)} (\{token.symbol(wallet)})")
    println("its amounts carry \{decimals} decimals")
  } catch {
    Abi(e) => println("that address is not an ERC-20: \{e}")
    Rpc(e) => println("the wallet said: \{e}")
    e => println("error: \{e}")
  }
}
```

`Erc20` lives in its own package, `poteto0/endor/contract/erc20`, and is a
preset over `Contract`, which is `eth_call` / `eth_sendTransaction`
with the arguments encoded and the answer decoded. Amounts are `BigInt` in the
token's smallest unit — `decimals` says where the point goes, and scaling it for
a human stays out of the SDK, exactly as it does for `Wei`. `transfer` and
`approve` sign, so they prompt and answer with a `TxHash`.

Any other contract is one `call` away, with the types spelled out:

```mbt-example
async fn owner_of(
  wallet : @browser.BrowserProvider,
  nft : @endor.Address,
  id : BigInt,
) -> @endor.Address? raise @contract.ContractError {
  let values = @contract.Contract::new(nft).call(
    wallet,
    name="ownerOf",
    inputs=[Uint(256)],
    args=[Uint(id)],
    outputs=[Address],
  )
  guard values is [Address(owner)] else { return None }
  Some(owner)
}
```

A contract that is not deployed yet is one `deploy` away, since a transaction
with no recipient deploys its `data`:

```mbt-example
async fn put_on_chain(
  wallet : @browser.BrowserProvider,
  me : @endor.Address,
  code : @endor.Hex,     // the creation code, from your compiler's artifact
) -> @endor.Address raise @contract.ContractError {
  let deployed = @contract.deploy(
    wallet,
    from=me,
    bytecode=code,
    inputs=[Uint(256)],  // the constructor's parameters, encoded behind the code
    args=[Uint(1000N)],
  )
  deployed.address()
}
```

`deploy` prompts, broadcasts, and waits for the receipt, because the address
only exists once the transaction is mined — `@contract.send_deployment` is the
same broadcast without the wait, for a UI that wants the `TxHash` while the
deployment is still pending.

The encoding underneath is `endor/abi`, usable on its own when the call goes out
some other way: `@abi.encode_call(name~, inputs~, args~)` builds the calldata,
`@abi.decode(outputs, data)` reads an answer back, `@abi.selector(sig)` and
`@abi.event_topic(sig)` hash a signature into the four bytes a call starts with
and the topic an event is logged under.

## Reading state without an ABI

```mbt-example
async fn total_supply(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
) -> Unit {
  try {
    // `totalSupply()` — the selector, spelled out
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

```mbt-example
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

The `TxHash` you get back says the transaction was _broadcast_, not mined. What
it did is in its receipt.

## Waiting for the receipt

```mbt-example
async fn transfer(
  wallet : @browser.BrowserProvider,
  request : @endor.TransactionRequest,
) -> Unit {
  try {
    let hash = @provider.send_transaction(wallet, request)
    // polls eth_getTransactionReceipt until the transaction is mined
    let receipt = @provider.wait_for_receipt(wallet, hash)
    match receipt.status {
      Success => println("mined in block \{receipt.block_number}")
      // a reverted transaction is mined, and still paid for
      Reverted => println("reverted, burning \{receipt.gas_used}")
    }
  } catch {
    Timeout(why) => println("gave up waiting: \{why}")
    e => println("error: \{e}")
  }
}
```

`wait_for_receipt` takes `confirmations` (1 by default — the receipt's own
block), and `timeout` / `poll_interval` in milliseconds. Running out of time
raises `Timeout`, which is deliberately not the same answer as the `None` that
`transaction_receipt` gives for a transaction with no receipt _yet_.

The receipt carries where the transaction landed (`block_number`, `block_hash`),
what it cost (`gas_used`, `effective_gas_price`), what it emitted (`logs`) and,
for a deployment, the `contract_address` the code now lives at. Blocks read back
with `block_by_number` / `block_by_hash`, which answer `None` for a block the
node does not know.

## Signing a message

```mbt-example
async fn login(
  wallet : @browser.BrowserProvider,
  who : @endor.Address,
) -> Unit {
  try {
    // personal_sign — the wallet shows the text and signs it with `who`'s key
    let signature = @provider.sign_message(wallet, who, "login to example.com")
    println("signed as \{signature}")
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

The message is signed EIP-191 style: the wallet prefixes it with
`"\x19Ethereum Signed Message:\n" + length` before hashing, so a signature
produced this way can never be a valid transaction. It travels as the UTF-8
bytes of the message in hex, which is what lets the wallet show the user the
text they are agreeing to, and the 65-byte signature comes back as `Hex` for
your backend to verify.

EIP-712 typed data is `sign_typed_data`, which takes an `@endor.TypedData` and
sends it to `eth_signTypedData_v4`:

```mbt-example
fn permit(
  token : @endor.Address,
  holder : @endor.Address,
) -> @endor.TypedData raise @endor.CodecError {
  @endor.TypedData::new(
    @endor.TypedDataDomain::new(
      name="Endor",
      chain_id=@endor.ChainId::mainnet(),
      verifying_contract=token,
    ),
    primary_type="Permit",
    types={
      "Permit": [
        @endor.TypedDataField::new("holder", "address"),
        // a uint256 past 2^53 travels as a string, since a JSON number cannot
        // hold one without losing precision
        @endor.TypedDataField::new("value", "uint256"),
      ],
    },
    message={ "holder": holder.to_json(), "value": "1000000000000000000" },
  )
}
```

Building the document validates it — `primaryType` resolves, every field type is
defined, and the message matches the type it claims to be — so a field with the
wrong type is reported by name here rather than as an opaque wallet-side error.
The `EIP712Domain` entry is derived from the domain, so the type and the value
cannot disagree. The wallet hashes the document, so nothing is hashed here.

## Switching chains

```mbt-example
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

## Reacting to wallet changes

```mbt-example
fn watch(wallet : @browser.BrowserProvider) -> @provider.Subscription {
  // accountsChanged: the user switched account, or revoked the dapp's access
  let sub = @provider.on_accounts_changed(wallet, accounts => {
    match accounts.get(0) {
      Some(addr) => println("now \{addr}") // most recently selected first
      None => println("disconnected") // an empty array ⇒ permission revoked
    }
  })
  // chainChanged: everything read from the old chain is about another one now
  let _ = @provider.on_chain_changed(wallet, chain => {
    println("chain \{chain.to_hex()}")
  })
  // disconnect: a ProviderRpcError, mapped like any other wallet-side failure
  let _ = @provider.on_disconnect(wallet, error => println("gone: \{error}"))
  sub // `sub.unsubscribe()` stops that one handler; calling it twice is safe
}
```

Every read above answers for the wallet's state _at that moment_, and the user
can change it from under you at any time — so these three EIP-1193 events are how
you learn your answers went stale. Each takes a plain callback and hands back a
`Subscription`: no UI framework, nothing to wire up, just a thunk your own
lifecycle can call when it tears down.

The SDK is stateless, which is the part worth knowing: it caches no current
account and no current chain, so subscribing reads no initial value and the
handler is the only place a new one arrives. Read the starting point with
`@provider.accounts` / `@provider.chain_id` and hold it yourself. A payload that
fails to decode is dropped rather than raised — an event arrives outside any call
you made, so there is nowhere to raise to — and the subscription stays live.

[`examples/get-address`](https://github.com/poteto0/endor.mbt/tree/main/examples/get-address)
does exactly this against a real wallet: it holds the account and chain in
signals, subscribes on connect, and unsubscribes when the wallet goes away.

## Scope

The reads are wrapped in typed helpers: accounts (`eth_requestAccounts`,
`eth_accounts`), the current chain (`eth_chainId`), and the account and chain
state behind `eth_getBalance`, `eth_blockNumber`, `eth_getTransactionCount`,
`eth_gasPrice` and `eth_getCode`. On top of those, `call` / `estimate_gas`
evaluate a request without broadcasting it, `send_transaction` broadcasts one,
`switch_chain` / `add_chain` / `switch_or_add_chain` move the wallet between
chains, `transaction_receipt` / `wait_for_receipt` and `block_by_number` /
`block_by_hash` read what was mined, and `on_accounts_changed` /
`on_chain_changed` / `on_disconnect` subscribe to the provider events, and
`sign_message` / `sign_typed_data` ask the wallet for a signature over a message
or a validated `TypedData` document. Above all
of that, `endor/abi` encodes and decodes ABI values and `endor/contract` turns
them into typed contract calls, with an `Erc20` preset. `Provider::request`
reaches any method the SDK does not wrap, with raw `Json`.

**→ [Reference](https://endor.poteto-mahiro.com/reference/)** for the full list,
what each helper returns, and how to use the escape hatch.
**→ [Not wrapped yet](https://endor.poteto-mahiro.com/reference/not-wrapped/)**
for what is missing and why, and
[`docs/roadmap.md`](https://github.com/poteto0/endor.mbt/blob/main/docs/roadmap.md)
for where it sits in the plan.
**→ [Versioning policy](https://endor.poteto-mahiro.com/reference/versioning/)**
for what counts as a breaking change while this is still `0.x`.

## Layout

| Package                  | Contents                                                                                                    |
| ------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `endor` (root)           | re-exports the domain types, so they can be spelled `@endor.Address`                                        |
| `endor/types`            | `Address`, `Hex`, `ChainId`, `Wei`, `Quantity`, `BlockTag`, `CallRequest`, `ChainParams` and their codecs   |
| `endor/codec`            | the wire's arithmetic: hex digits, the 32-byte word, two's complement, the ABI's width rules                 |
| `endor/eip712`           | `TypedData` — the EIP-712 document, its validation and the digest a wallet signs                             |
| `endor/crypto`           | `keccak256` — the hash Ethereum builds its identifiers from; a leaf package, depending on nothing else here |
| `endor/abi`              | ABI encode / decode, function selectors and event topics — `AbiType`, `AbiValue`, `AbiError`                |
| `endor/contract`         | `Contract` — typed calls over the ABI layer — `deploy`, and the `Erc20` preset                              |
| `endor/provider`         | `Provider` / `EventSource` traits, `ProviderError`, typed RPC and event helpers, `MockProvider`             |
| `endor/provider/browser` | `BrowserProvider` — the injected `globalThis.ethereum`, wrapped                                             |
| `endor/ffi/js`           | the only `extern "js"` code: `globalThis.ethereum` access, `request`, `on` / `removeListener`, `spawn`      |

`endor`, `endor/crypto`, `endor/codec`, `endor/types`, `endor/eip712`,
`endor/abi`, `endor/contract` and `endor/provider` are backend-agnostic;
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
just ut        # unit tests — no browser or wallet needed
just build     # build for js, including the example
just ci        # test, format, check, and refresh generated interfaces
just docs-dev  # the documentation site, demos and all, on localhost:7777
```