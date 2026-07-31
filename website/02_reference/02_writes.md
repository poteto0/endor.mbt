---
title: Writes
description: send_transaction, the fee enum, and the wait that turns a hash into an outcome.
---

# Writes

One function broadcasts, and it is the only one on this site that spends the
user's money.

| Function                            | JSON-RPC method       | Returns          |
| ----------------------------------- | --------------------- | ---------------- |
| `@provider.send_transaction(p, req)` | `eth_sendTransaction` | `@endor.TxHash` |

```moonbit
async fn send(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  to : @endor.Address,
) -> @endor.TxHash raise {
  @provider.send_transaction(
    wallet,
    @endor.TransactionRequest::new(
      from, // the signer (required)
      to~, // absent ⇒ deploy `data`
      value=@endor.Wei::from_int(1000), // wei to send
      // data=, gas=, nonce=, fee= are optional too
    ),
  )
}
```

The answer is an `@endor.TxHash`: a `Hex` narrowed to exactly 32 bytes, so a
wallet answering with something else is caught here rather than at whichever RPC
is later handed the value. It means the transaction was *broadcast* — it can
still be dropped or replaced, and what it actually did is in its receipt.

Leaving `to` out is how a transaction **deploys** the contract in `data`. That is
[`@contract.deploy`](./abi/#deploying) with the encoding done for you.

## Fees

`fee=` is an `@endor.Fee` rather than three optional fields, because the two fee
markets are mutually exclusive on the wire — geth rejects a request carrying both
`gasPrice` and `maxFeePerGas` / `maxPriorityFeePerGas` — and an enum cannot spell
that combination:

| `Fee`                                                  | On the wire                            |
| ------------------------------------------------------ | -------------------------------------- |
| `Auto` (default)                                       | no fee field; the wallet decides       |
| `Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~)` | `maxFeePerGas`, `maxPriorityFeePerGas` |
| `Legacy(gas_price~)`                                   | `gasPrice`                             |

`Auto` is what a dapp normally wants. Since London, geth defaults a request with
no fee field to an EIP-1559 (dynamic-fee, type `0x02`) transaction — taking
`maxPriorityFeePerGas` from its own tip oracle and `maxFeePerGas` from
`2 * baseFee + tip` — and only builds a legacy transaction when `gasPrice` is
given. So `Legacy` means "opt out of EIP-1559", for a chain that never forked to
London; it is not the default and should not be reached for by habit.

## Waiting

`wait_for_receipt` is the other half of `send_transaction` — it polls until the
transaction is mined:

```moonbit
async fn send_and_wait(
  wallet : @browser.BrowserProvider,
  request : @endor.TransactionRequest,
) -> @endor.TransactionReceipt raise {
  let hash = @provider.send_transaction(wallet, request)
  @provider.wait_for_receipt(
    wallet,
    hash,
    confirmations=1, // the receipt's own block counts as the first
    timeout=60_000, // ms in total
    poll_interval=1_000, // ms between polls
  )
}
```

Asking for more than one confirmation waits for the head to move that far past
the receipt's block, which is what makes a reorg unlikely to take it back out.
Asking for fewer than one is a caller error and raises rather than being read as
one.

Running out of time raises `ProviderError::Timeout`, deliberately distinct from
the `None` of `transaction_receipt`: `None` says there is no receipt *right now*,
`Timeout` says there was none for as long as the caller allowed.

## Reverted is mined

A transaction that **reverted still has a receipt**, so a successful wait is not
a successful transaction:

```moonbit
fn did_it_work(receipt : @endor.TransactionReceipt) -> Bool {
  match receipt.status {
    Success => true
    // mined, and it still paid for the gas it burned getting there
    Reverted => false
  }
}
```

`receipt.status` is the field to check, and forgetting to check it is the most
common way a dapp reports success for something that failed.

## Logs

`logs` is an array of `@endor.Log`, each with its raw `topics` and `data`.
`@abi.event_topic("Transfer(address,address,uint256)")` is what `topics[0]` is
matched against to find the logs of one event, and `@abi.decode` reads the
non-indexed arguments out of `data`. Pairing indexed arguments back up with their
topics is [not wrapped yet](./not-wrapped/).
