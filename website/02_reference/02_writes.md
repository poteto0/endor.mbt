---
title: Writes
description: send_transaction, the fee enum, and the wait that turns a hash into an outcome.
---

# Writes

One function asks the wallet to sign and broadcast, and it is the only one on
this site that spends the user's money. The other, further down, broadcasts a
transaction somebody else already signed and paid for.

| Function                                  | JSON-RPC method          | Returns         |
| ----------------------------------------- | ------------------------ | --------------- |
| `@provider.send_transaction(p, req)`      | `eth_sendTransaction`    | `@endor.TxHash` |
| `@provider.send_raw_transaction(p, hex)`  | `eth_sendRawTransaction` | `@endor.TxHash` |
| `client.send(to~, value~)`                | whichever the account needs | `@endor.TxHash` |

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

## Or through a client

`send_transaction` is the transport call: it names the sender on every use, and
it only reaches a key the endpoint itself holds. `@wallet.WalletClient` pairs a
transport with an account once and picks the route from the account:

```moonbit
async fn send_via_client(
  browser_wallet : @browser.BrowserProvider,
  to : @endor.Address,
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::connect(browser_wallet)
  client.send(to~, value=@endor.Wei::from_int(1000))
}
```

An account behind a wallet takes the `eth_sendTransaction` path above. An
account holding a key — `@local.LocalAccount` — signs in this process and the
bytes go out as `eth_sendRawTransaction`. The call is the same either way; see
[Sign with a local key](../../cookbook/local-account/).

What is left out is filled in by whoever is going to sign. A wallet holds the
key and prices the transaction itself, so `send` hands it the request as it
stands and asks the node for nothing. A local key means this SDK has to decide
every number before it signs, so that call goes through `prepare` first.

`client.prepare(…)` is that half on its own: it fills in the chain id, the nonce
(from the **pending** count), the fee and the gas from the node, and answers an
`@endor.UnsignedTransaction`. Anything passed in is used as given and not asked
about. The fee decides the format: an EIP-1559 pair builds a type-`0x02`
envelope, a flat `gasPrice` an EIP-155 legacy transaction. It is worth calling
directly against a wallet too, when the point is to pin the numbers down and
show them before prompting.

`prepare` builds those two formats and no other. A type-`0x04` transaction —
the EIP-7702 one, which carries a list of authorizations — is built by hand
through `UnsignedTransaction::eip7702` and signed by an account holding its own
key: [Delegate an EOA](../../cookbook/delegate-eoa/).

## Broadcasting something already signed

| Function                                | JSON-RPC method          | Returns         |
| --------------------------------------- | ------------------------ | --------------- |
| `@provider.send_raw_transaction(p, raw)` | `eth_sendRawTransaction` | `@endor.TxHash` |

`raw` is a signed, RLP-encoded transaction. No wallet is involved and nothing
prompts — whoever signed it pays for it. The SDK
[holds no keys](./not-wrapped/), so it never builds one: this is the entrance for
a transaction signed somewhere else, which is how a *relayer* submits work
somebody else authorized.

```moonbit
async fn relay(
  wallet : @browser.BrowserProvider,
  signed : @endor.Hex,
) -> @endor.TxHash raise {
  @provider.send_raw_transaction(wallet, signed)
}
```

Like `send_transaction`, the hash says the transaction was broadcast and nothing
more; `wait_for_receipt` below is what turns it into an outcome.

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
London; it is not the default and should not be reached for by habit. Both paths
honour it: a wallet is sent `gasPrice`, and a local key signs the legacy
envelope, always with EIP-155's chain-bound `v` — the SDK does not build a
pre-155 transaction, which any chain would replay.

### Pricing one yourself

When the wallet's answer is not the one to send — bidding above the market
during congestion, replacing a stuck transaction, pricing one as a relayer with
no wallet to ask — `estimate_fees` builds the `Fee` the wallet would have built:

```moonbit
async fn send_at_market(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  to : @endor.Address,
) -> @endor.TxHash raise {
  @provider.send_transaction(
    wallet,
    @endor.TransactionRequest::new(
      from,
      to~,
      value=@endor.Wei::from_ether("0.01"),
      fee=@provider.estimate_fees(wallet),
    ),
  )
}
```

It reads the latest block's `baseFeePerGas` and answers `Eip1559` with the tip
`eth_maxPriorityFeePerGas` suggests and a cap of `2 * baseFee + tip`. **The
doubling is geth's own default** for a request that names no cap, not something
EIP-1559 says; it covers a base fee rising for six consecutive full blocks. A
chain with no base fee, or one that keeps it at zero, has no 1559 market to price
into and gets `Legacy(gas_price=eth_gasPrice)` instead.

The estimate is a snapshot. The base fee moves every block, so a cap that was
generous when it was built can still be too low when the transaction is mined.

The two materials it is built from are callable on their own:

| Function                                   | JSON-RPC method             | Returns                |
| ------------------------------------------ | --------------------------- | ---------------------- |
| `@provider.max_priority_fee_per_gas(p)`    | `eth_maxPriorityFeePerGas`  | `@endor.Wei?`          |
| `@provider.fee_history(p, block_count=…)`  | `eth_feeHistory`            | `@endor.FeeHistory`    |

`max_priority_fee_per_gas` answers `None` — not an error, not a zero tip — when
the node does not implement the method, which it is allowed not to: it is a geth
extension rather than a standardized call. (`estimate_fees` then takes the tip
from `eth_gasPrice` less the base fee, which is the same quantity, since that is
how the suggested price was built.)

`fee_history` is what a caller that wants to decide the tip itself reads. Its
`reward_percentiles` are percentiles of each block's gas sorted by effective tip,
so `[50.0]` asks what the transaction paying for the median unit of gas tipped:

```moonbit
async fn median_tip_over_ten_blocks(
  wallet : @browser.BrowserProvider,
) -> @endor.Wei? raise {
  let history = @provider.fee_history(
    wallet,
    block_count=10,
    reward_percentiles=[50.0],
  )
  // one row per block — oldest first, so the newest is the last — and one
  // column per percentile asked for
  match history.reward {
    Some([.., [newest_median, ..]]) => Some(newest_median)
    _ => None // no percentile was asked for, or the node kept no blocks
  }
}
```

`base_fee_per_gas` is deliberately one element longer than the other arrays: its
last element is the base fee of the block *after* the newest one, which the
protocol already fixes, and that is the one a fee for the next block is built
from. Asking for no percentile at all is the cheap form, and the answer then
carries no `reward` — `None` rather than a list of empty lists.

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
matched against to find the logs of one event, and
[`@abi.decode_log`](./abi/#reading-a-log) reads one back as the arguments it was
emitted with — the `indexed` ones out of `topics`, the rest out of `data`.
