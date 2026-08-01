---
title: Send ETH
description: Broadcast a transaction, then wait for the receipt that says what it did.
islands:
  - units
  - send_eth
---

# Send ETH

The first call that spends the user's money, and so the first that always
prompts.

<div class="alert alert--warning" role="note">
  <div class="alert__title">This one is real</div>
  <div class="alert__description">

The demo below broadcasts a transaction from your wallet, for the amount you
type. Switch to a testnet first. Every other demo on this site only reads.

  </div>
</div>

<Island name="send_eth" trigger="load" />

## The call

```moonbit
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

`from` is required — it is the account that signs, and a wallet holding several
needs to be told which. Everything the request leaves out (`nonce`, `gas`, the
fees) the wallet fills in.

What comes back is a `TxHash`: a `Hex` narrowed to exactly 32 bytes, so a wallet
answering with something else is caught here rather than by whichever RPC is
handed the value later. It says the transaction was **broadcast**. It can still
be dropped or replaced, and what it actually did is in its receipt.

## Amounts are wei

`Wei::from_int(1000)` is a thousand wei, which is nothing at all. One ether is
`10^18` of them:

```moonbit
fn one_ether() -> @endor.Wei {
  @endor.Wei::from_bigint(BigInt::from_string("1000000000000000000"))
}
```

The SDK never scales an amount for you. Turning `"0.001"` into wei is a
presentation concern, and it belongs in the layer that has a text input in it.

**Try it:** the first box is the amount a person typed, the second is the
currency's `decimals` — 18 for ether, 6 for USDC. Ask for a digit finer than the
currency can carry and it is refused rather than rounded, because silently
dropping a digit of somebody's money is worse than making them retype it.

<Island name="units" trigger="visible" />

That widget is this function, which is the one you would write:

```moonbit
/// Parse a human amount into whole wei, or `None` when it is not a decimal
/// number that 18 decimals can carry.
fn wei_of_ether(amount : String) -> @endor.Wei? {
  let whole = StringBuilder::new()
  let fraction = StringBuilder::new()
  let mut after_point = false
  let mut digits = 0
  for c in amount.trim() {
    if c == '.' {
      guard !after_point else { return None }
      after_point = true
    } else if c.is_ascii_digit() {
      digits += 1
      (if after_point { fraction } else { whole }).write_char(c)
    } else {
      return None
    }
  }
  guard digits > 0 else { return None }
  // more decimals than wei can carry is an error, not something to round:
  // silently dropping a digit of somebody's money is worse than a retype
  let padding = 18 - fraction.to_string().length()
  guard padding >= 0 else { return None }
  let scaled = whole.to_string() + fraction.to_string() + "0".repeat(padding)
  Some(@endor.Wei::from_bigint(BigInt::from_string("0" + scaled)))
}
```

Parse before you prompt. The demo above builds both the address and the amount
into domain types first, so a typo costs no popup.

## Fees

`fee=` is an `@endor.Fee`, not three optional fields, because the two fee markets
are mutually exclusive on the wire — geth rejects a request carrying both
`gasPrice` and `maxFeePerGas`:

| `Fee`                                                  | On the wire                            |
| ------------------------------------------------------ | -------------------------------------- |
| `Auto` (default)                                       | no fee field; the wallet decides       |
| `Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~)` | `maxFeePerGas`, `maxPriorityFeePerGas` |
| `Legacy(gas_price~)`                                   | `gasPrice`                             |

`Auto` is what a dapp normally wants: since London, a node given no fee field
builds an EIP-1559 (type `0x02`) transaction, taking the tip from its own oracle.
`Legacy` means "opt out of EIP-1559", for a chain that never forked — not
something to reach for by habit.

```moonbit
fn explicit_fees(from : @endor.Address, to : @endor.Address) -> @endor.TransactionRequest {
  @endor.TransactionRequest::new(
    from,
    to~,
    value=@endor.Wei::from_int(1000),
    // 30 gwei and 1 gwei. `Wei::from_int` takes an `Int`, and 30 gwei does not
    // fit in one — every amount past ~2 ETH is a `BigInt`.
    fee=Eip1559(
      max_fee_per_gas=@endor.Wei::from_bigint(BigInt::from_string("30000000000")),
      max_priority_fee_per_gas=@endor.Wei::from_int(1_000_000_000),
    ),
  )
}
```

## Estimating first

`estimate_gas` simulates the same request without broadcasting it, so it costs
nothing and prompts nobody. A transaction that would revert fails here — which
makes it a cheap pre-flight check before asking anyone to sign:

```moonbit
async fn will_it_work(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  to : @endor.Address,
) -> Bool {
  let req = @endor.CallRequest::new(to, from~, value=@endor.Wei::from_int(1000))
  let _ = @provider.estimate_gas(wallet, req) catch {
    _ => return false
  }
  true
}
```

## Then wait

A hash is not an outcome. [Wait for a receipt](./receipts/) is the other half.
