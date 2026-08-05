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
`10^18` of them, and `from_ether` is how you say so:

```moonbit
// every one of these raises `CodecError`: the amount is a string, and a string
// can be something other than a number
fn amounts() -> Array[@endor.Wei] raise {
  [
    @endor.Wei::from_ether("1"), // 1000000000000000000 wei
    @endor.Wei::from_ether("0.05"),
    @endor.Wei::from_gwei("30"), // gas prices are quoted here
    // any other scale — a token's own `decimals` — is passed in
    @endor.Wei::from_units("1.5", decimals=6),
  ]
}
```

The amount is a `String` and never a `Double`. `0.1` is not representable in
binary, so a `Double` has lost the value before the SDK could see it, and the
digit that goes missing is a digit of somebody's money. For the same reason an
amount **finer** than the scale raises `InvalidDecimal` instead of being
truncated: `from_ether("1.0000000000000000001")` is refused, because dropping
that digit silently is worse than making the user retype it.

`to_units` is the inverse, with trailing zeros folded — `1500000000000000000` at
18 decimals is `"1.5"`, not `"1.500000000000000000"`. What comes back is the
number and nothing else: no thousands separators, no symbol, no currency. Those
are the application's, and an SDK that guessed at them would be wrong in some
locale.

**Try it:** the first box is the amount a person typed, the second is the
currency's `decimals` — 18 for ether, 6 for USDC.

<Island name="units" trigger="visible" />

## Take an amount from a text box

The recipe that widget is: parse before you prompt, so a typo costs no popup and
the wallet is only asked once everything is a domain type.

```moonbit
async fn send_typed_amount(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  typed_to : String,
  typed_amount : String,
) -> Unit {
  // both of these raise `CodecError`, and neither has touched the wallet yet
  let to = @endor.Address::from_string(typed_to) catch {
    e => {
      println("that is not an address: \{e}")
      return
    }
  }
  let value = @endor.Wei::from_ether(typed_amount) catch {
    // `InvalidDecimal` is the whole story here: not a number, or finer than
    // ether's eighteen decimals
    e => {
      println("that is not an amount: \{e}")
      return
    }
  }
  println("about to send \{value.to_ether()} ETH")
  let hash = @provider.send_transaction(
    wallet,
    @endor.TransactionRequest::new(from, to~, value~),
  ) catch {
    UserRejected => {
      println("the user declined")
      return
    }
    e => {
      println("error: \{e}")
      return
    }
  }
  println("broadcast as \{hash}")
}
```

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
fn explicit_fees(
  from : @endor.Address,
  to : @endor.Address,
) -> @endor.TransactionRequest raise {
  @endor.TransactionRequest::new(
    from,
    to~,
    value=@endor.Wei::from_int(1000),
    // 30 gwei and 1 gwei, spelled as the unit they are always quoted in
    fee=Eip1559(
      max_fee_per_gas=@endor.Wei::from_gwei("30"),
      max_priority_fee_per_gas=@endor.Wei::from_gwei("1"),
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
