---
title: Wait for a receipt
description: A hash says broadcast. A receipt says what happened — including that it reverted.
---

# Wait for a receipt

`send_transaction` answers with a `TxHash`, which means the transaction was
handed to the network. It can still be dropped, replaced, or mined and reverted.
The receipt is where the outcome is.

The [Send ETH](./send-eth/) demo does this end to end: after it broadcasts, the
`Receipt` field fills in with the block and the gas, or with the fact that it
reverted.

## Waiting

```moonbit
async fn transfer_and_wait(
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

**A successful wait is not a successful transaction.** A transaction that
reverted has a receipt too, and paid for the gas it burned getting there.
`receipt.status` is the field to check, and forgetting to check it is the most
common way a dapp reports success for something that failed.

## The knobs

```moonbit
async fn wait_harder(
  wallet : @browser.BrowserProvider,
  hash : @endor.TxHash,
) -> @endor.TransactionReceipt raise {
  @provider.wait_for_receipt(
    wallet,
    hash,
    confirmations=3, // the receipt's own block counts as the first
    timeout=120_000, // ms in total
    poll_interval=2_000, // ms between polls
  )
}
```

Asking for more than one confirmation waits for the head to move that far past
the receipt's block, which is what makes a reorg unlikely to take it back out.
Asking for fewer than one is a caller error and raises rather than being read as
one.

## Timeout is not None

There are two ways to have no receipt, and they mean different things:

```moonbit
async fn not_yet_versus_gave_up(
  wallet : @browser.BrowserProvider,
  hash : @endor.TxHash,
) -> Unit {
  // `None` — there is no receipt *right now*. Perfectly normal a second after
  // broadcasting, and not an error.
  match (@provider.transaction_receipt(wallet, hash) catch { _ => None }) {
    Some(receipt) => println("already mined: \{receipt.block_number}")
    None => println("still pending")
  }
  // `Timeout` — there was no receipt for as long as the caller allowed. That is
  // a decision the caller made, so it is raised rather than returned.
  let _ = @provider.wait_for_receipt(wallet, hash, timeout=5_000) catch {
    Timeout(why) => {
      println("not mined within 5s: \{why}")
      return
    }
    e => {
      println("error: \{e}")
      return
    }
  }
  println("mined")
}
```

## What a receipt carries

```moonbit
fn read_receipt(receipt : @endor.TransactionReceipt) -> Unit {
  // where it landed
  println("block \{receipt.block_number} (\{receipt.block_hash})")
  // what it cost. `effective_gas_price` is optional: a pre-London chain has no
  // such thing to report.
  let price = match receipt.effective_gas_price {
    Some(wei) => "\{wei.to_bigint()} wei/gas"
    None => "no effective price"
  }
  println("gas \{receipt.gas_used} at \{price}")
  // for a deployment — present exactly when `to` was absent
  match receipt.contract_address {
    Some(addr) => println("deployed at \{addr}")
    None => println("not a deployment")
  }
  // what it emitted
  println("\{receipt.logs.length()} log(s)")
}
```

`logs` is an array of `@endor.Log`, each with its raw `topics` and `data`.
Matching one event out of them is `@abi.event_topic`:

```moonbit
fn transfers_in(receipt : @endor.TransactionReceipt) -> Array[@endor.Log] {
  let topic = @abi.event_topic("Transfer(address,address,uint256)")
  receipt.logs.filter(log => log.topics.get(0) is Some(t) && t == topic)
}
```

`@abi.decode` reads the non-indexed arguments out of a log's `data`. Pairing the
*indexed* ones back up with their topics is not wrapped yet — it is on the
[not-wrapped list](/reference/not-wrapped/).

## Blocks

```moonbit
async fn head(wallet : @browser.BrowserProvider) -> Unit raise {
  // `None` for a block the node does not have — the same wire fact as a
  // receipt that does not exist yet
  match @provider.block_by_number(wallet) {
    Some(block) => println("head: \{block.transactions.length()} transactions")
    None => println("no such block")
  }
}
```

A `Block` carries the header — `number`, `hash`, `parent_hash`, `timestamp`,
`miner`, `gas_limit`, `gas_used`, `base_fee_per_gas` — and `transactions` as a
list of `TxHash`. `number` and `hash` are absent for the *pending* block, which
has not been sealed and so has neither.
