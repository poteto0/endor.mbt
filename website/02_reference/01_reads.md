---
title: Reads
description: Accounts, balances, nonces, code, calls, blocks and receipts — none of which prompt or cost anything.
---

# Reads

Nothing on this page spends money, and only `request_accounts` can open a popup.

## Accounts and chain

| Function                              | JSON-RPC method           | Returns                 |
| ------------------------------------- | ------------------------- | ----------------------- |
| `@provider.request_accounts(p)`       | `eth_requestAccounts`     | `Array[@endor.Address]` |
| `@provider.require_account(p)`        | `eth_requestAccounts`     | `@endor.Address`        |
| `@provider.accounts(p)`               | `eth_accounts`            | `Array[@endor.Address]` |
| `@provider.chain_id(p)`               | `eth_chainId`             | `@endor.ChainId`        |

`request_accounts` prompts the wallet to connect if it is not connected yet;
`accounts` never prompts and returns an empty array when the dapp is not
authorized. `require_account` is `request_accounts` with the empty case already
turned into an error.

## Account and chain state

| Function                              | JSON-RPC method           | Returns             |
| ------------------------------------- | ------------------------- | ------------------- |
| `@provider.balance(p, who)`           | `eth_getBalance`          | `@endor.Wei`        |
| `@provider.block_number(p)`           | `eth_blockNumber`         | `UInt64`            |
| `@provider.transaction_count(p, who)` | `eth_getTransactionCount` | `UInt64` (nonce)    |
| `@provider.gas_price(p)`              | `eth_gasPrice`            | `@endor.Wei`        |
| `@provider.code(p, who)`              | `eth_getCode`             | `@endor.Hex`        |
| `@provider.is_contract(p, who)`       | `eth_getCode`             | `Bool`              |

`is_contract` is `code` with an emptiness test: an externally owned account has
no bytecode.

## Reading at a block

`balance`, `transaction_count`, `code` and `is_contract` all take an optional
`block=`, an `@endor.BlockTag`:

```moonbit
async fn at_a_block(
  wallet : @browser.BrowserProvider,
  who : @endor.Address,
) -> Unit raise {
  // Pending is the one to use for a nonce: it counts transactions the wallet
  // has broadcast but that are not mined yet
  let nonce = @provider.transaction_count(wallet, who, block=Pending)
  let then = @provider.balance(wallet, who, block=Number(21962336))
  println("nonce \{nonce}, balance then \{then.to_bigint()}")
}
```

The tags are `Latest` (the default), `Pending`, `Earliest`, `Safe`, `Finalized`
and `Number(n)`.

`call` takes the same `block=`; `estimate_gas` does not, since an estimate is
only meaningful against current state.

## Calls and gas estimation

| Function                         | JSON-RPC method   | Returns           |
| -------------------------------- | ----------------- | ----------------- |
| `@provider.call(p, req)`         | `eth_call`        | `@endor.Hex`      |
| `@provider.estimate_gas(p, req)` | `eth_estimateGas` | `@endor.Quantity` |

Both take an `@endor.CallRequest` — the transaction-shaped object the node
evaluates against its state instead of broadcasting. Neither needs a signature,
so neither prompts:

```moonbit
async fn total_supply(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
) -> Unit raise {
  let req = @endor.CallRequest::new(
    token, // to (required)
    data=@endor.Hex::from_string("0x18160ddd"), // `totalSupply()`, spelled out
  )
  let ret = @provider.call(wallet, req) // return data, as Hex
  let gas = @provider.estimate_gas(wallet, req).to_uint64()
  println("\{ret.byte_length()} bytes back, \{gas} gas to run it")
}
```

`from` (what the callee sees as `msg.sender`) and `value` are optional too, and
what the caller leaves out stays out of the request rather than being sent as
`null`.

`data` is calldata and the answer is return data: a selector plus ABI-encoded
arguments in, raw bytes out. [ABI and contracts](./abi/) is the same thing with
the encoding done for you.

A call that reverts comes back as a `ProviderError`, which is what makes
`estimate_gas` a cheap pre-flight check before asking anyone to sign.

## Receipts and blocks

| Function                                 | JSON-RPC method             | Returns                      |
| ---------------------------------------- | --------------------------- | ---------------------------- |
| `@provider.transaction_receipt(p, hash)` | `eth_getTransactionReceipt` | `@endor.TransactionReceipt?` |
| `@provider.wait_for_receipt(p, hash)`    | the same, polled            | `@endor.TransactionReceipt`  |
| `@provider.block_by_number(p, block?)`   | `eth_getBlockByNumber`      | `@endor.Block?`              |
| `@provider.block_by_hash(p, hash)`       | `eth_getBlockByHash`        | `@endor.Block?`              |

The three `?` returns are all the same wire fact: a node answers `null` for a
receipt that does not exist yet and for a block it does not have, and neither is
an error.

A `TransactionReceipt` carries `block_number` / `block_hash`, `gas_used` /
`cumulative_gas_used` / `effective_gas_price`, `from` / `to`, `contract_address`
(present exactly when `to` is absent, i.e. for a deployment), `status` and
`logs`. A `Block` carries the header — `number`, `hash`, `parent_hash`,
`timestamp`, `miner`, `gas_limit`, `gas_used`, `base_fee_per_gas` — and
`transactions` as a list of `TxHash`. `number` and `hash` are absent for the
*pending* block, which has not been sealed and so has neither.

Waiting is on the [Writes](./writes/) page, since it is the other half of
`send_transaction`.
