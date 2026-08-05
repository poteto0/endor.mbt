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
| `@provider.storage_at(p, who, slot)`  | `eth_getStorageAt`        | `@endor.Hex` (word) |

`is_contract` is `code` with an emptiness test: an externally owned account has
no bytecode.

`storage_at` reads one 32-byte slot straight out of the EVM, which is the only
way to see state a contract does not expose — no ABI declares a storage layout,
so what the word *means* is yours to know. A slot nobody ever wrote reads as
thirty-two zero bytes rather than as an absence. The use that motivates it is a
proxy's implementation address, which EIP-1967 puts at a fixed slot:

```moonbit
async fn implementation_of(
  wallet : @browser.BrowserProvider,
  proxy : @endor.Address,
) -> @endor.Hex raise {
  // keccak256("eip1967.proxy.implementation") - 1
  let slot = @endor.Hex::from_string(
    "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  )
  // the address is in the word's low 20 bytes
  @provider.storage_at(wallet, proxy, slot)
}
```

## Reading at a block

`balance`, `transaction_count`, `code`, `is_contract` and `storage_at` all take
an optional `block=`, an `@endor.BlockTag`:

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
| `@provider.block_transaction_count_by_number(p, block?)` | `eth_getBlockTransactionCountByNumber` | `UInt64?`   |
| `@provider.block_transaction_count_by_hash(p, hash)`     | `eth_getBlockTransactionCountByHash`   | `UInt64?`   |

The `?` returns are all the same wire fact: a node answers `null` for a receipt
that does not exist yet and for a block it does not have, and neither is an
error. A height past the head is the one place nodes disagree — some answer
`null` there and others, Anvil among them, call it a bad parameter and raise —
so `None` is the answer to expect from the counts, not the answer to rely on.

The two counts are `block_by_number(…).transactions.length()` with the hashes
left on the node: ask for them when the number is all you want.

A `TransactionReceipt` carries `block_number` / `block_hash`, `gas_used` /
`cumulative_gas_used` / `effective_gas_price`, `from` / `to`, `contract_address`
(present exactly when `to` is absent, i.e. for a deployment), `status` and
`logs`. A `Block` carries the header — `number`, `hash`, `parent_hash`,
`timestamp`, `miner`, `gas_limit`, `gas_used`, `base_fee_per_gas` — and
`transactions` as a list of `TxHash`. `number` and `hash` are absent for the
*pending* block, which has not been sealed and so has neither.

Waiting is on the [Writes](./writes/) page, since it is the other half of
`send_transaction`.

## Past logs

| Function                        | JSON-RPC method | Returns              |
| ------------------------------- | --------------- | -------------------- |
| `@provider.logs(p, filter)`     | `eth_getLogs`   | `Array[@endor.Log]`  |

A receipt only carries the logs of the one transaction it is a receipt for.
`logs` is how you read events that were emitted before the dapp was ever open:
a `@endor.LogFilter` says which blocks to look in, which contracts to accept
logs from, and what the indexed `topics` must be.

```moonbit
async fn recent_transfers(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
) -> Unit raise {
  let transfer = @endor.Topic::exactly(
    @abi.event_topic("Transfer(address,address,uint256)"),
  )
  let head = @provider.block_number(wallet)
  let filter = @endor.LogFilter::range(
    from_block=Number(head - 1000),
    address=[token],
    topics=[Some(transfer)],
  )
  for log in @provider.logs(wallet, filter) {
    println("block \{log.block_number}: \{log.data.byte_length()} bytes")
  }
}
```

A topic position is one of three things, and that is why `topics` is an
`Array[@endor.Topic?]` rather than an array of hashes:

- `Some(@endor.Topic::exactly(t))` — this position must be `t`
- `Some(@endor.Topic::any_of([a, b]))` — it may be either, the OR a single
  value cannot express
- `None` — anything, while *still occupying the position*, so that a constraint
  after it stays at its own index

`topics[0]` is the event signature hash for anything but an anonymous event, and
the rest are the `indexed` arguments in declaration order.

To search one block rather than a range, including a block a reorg dropped,
`@endor.LogFilter::at_block(hash)` sends `blockHash` instead — the RPC does not
accept it together with a range, which is why it is its own constructor and not
a fourth argument.

Every criterion is optional: `@endor.LogFilter::range()` is every log in the
latest block. That is rarely what you want, because **the limits are the
node's**. A public RPC caps how wide a range and how many logs it will answer
with, and refuses the request with an error of its own devising when you pass
them. The SDK sends the filter as given and does not split it up — narrowing the
search, or walking a wide range in chunks, is yours to do.

What a matched log *says* is [`@abi.decode_log`](./abi/#reading-a-log): it
pairs the indexed arguments back up with the topics filtered on here and reads
the rest out of `data`.
