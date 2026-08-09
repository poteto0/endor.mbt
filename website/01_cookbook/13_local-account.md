---
title: Sign with a local key
description: A private key in your own process, signing without a wallet — and the same client either way.
---

# Sign with a local key

Everything else in this cookbook assumes a wallet holds the key and the user
approves each prompt. A script, a backend or a test has no user and no
extension. It has a private key.

<div class="alert alert--warning" role="note">
  <div class="alert__title">A key in the page is a key anyone can take</div>
  <div class="alert__description">

Anything that can read a `LocalAccount` can sign anything at all with it, with
no prompt. That is the point in a backend and a disaster in a browser — there,
let the wallet hold the key. Never put a real key in code, in a repository, or
in a bundle a browser downloads.

  </div>
</div>

## The two lines that differ

A `WalletClient` is a transport and an account. Which account you give it is
the only thing that changes:

```moonbit
async fn pay_from_key(
  node : @http.HttpProvider[@endpoint.Endpoint],
  key : @endor.Hex,
  to : @endor.Address,
) -> @endor.TxHash raise {
  let account = @local.LocalAccount::new(key)
  let client = @wallet.WalletClient::new(node, account)
  client.send(to~, value=@endor.Wei::from_ether("0.01"))
}
```

```moonbit
async fn pay_from_wallet(
  browser_wallet : @browser.BrowserProvider,
  to : @endor.Address,
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::connect(browser_wallet)
  client.send(to~, value=@endor.Wei::from_ether("0.01"))
}
```

`send`, `sign_message` and `sign_typed_data` are the same calls on both. What
differs is where the signing happens, and that is the account's business.

## It is the account that decides, not the transport

It is tempting to branch on "is this a browser?". That is the wrong question.
An HTTP endpoint may hold keys — a local node with an account unlocked does —
and a browser page may hold a local key for a session or a burner. The two are
independent, and every pairing is valid:

| Transport | Account | What happens |
| --------- | ------- | ------------ |
| `http`    | `LocalAccount`   | signed here, sent as `eth_sendRawTransaction` |
| `http`    | `JsonRpcAccount` | the node signs, if it holds the key |
| `browser` | `JsonRpcAccount` | the wallet prompts, signs and broadcasts |
| `browser` | `LocalAccount`   | signed here, broadcast through the wallet's transport |

So the client asks the *account* what it is. The first row is the ordinary
shape for a backend; the third is the ordinary shape for a dapp.

## Where the key comes from

`LocalAccount::new` takes the 32 bytes of the scalar as `Hex` and derives the
address from them. You cannot hand it an address: an account that could claim
one its key does not sign for would be a bug waiting for a production balance.

```moonbit
fn account_from_env(key : String) -> @endor.Address raise {
  let account = @local.LocalAccount::new(@endor.Hex::from_string(key))
  account.address()
}
```

Anything that is not a key is refused before it can sign: the wrong width, zero,
or a scalar at or past the curve's order all raise
`@endor.AccountError::InvalidPrivateKey`.

## What still needs the node

Signing is local. Deciding *what* to sign is not.

A signature commits to the chain id, the nonce, the gas limit and both fee
caps, and only the node knows those. So `send` is a round trip even with the
key in hand — `prepare` asks for what you did not supply:

```moonbit
async fn pay_with_fixed_fees(
  node : @http.HttpProvider[@endpoint.Endpoint],
  account : @local.LocalAccount,
  to : @endor.Address,
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::new(node, account)
  let tx = client.prepare(
    to~,
    value=@endor.Wei::from_ether("0.01"),
    // supplied, so the node is not asked
    gas=@endor.Quantity::new(21000),
    fee=Eip1559(
      max_fee_per_gas=@endor.Wei::from_gwei("20"),
      max_priority_fee_per_gas=@endor.Wei::from_gwei("1"),
    ),
  )
  client.send_transaction(tx)
}
```

The nonce comes from the **pending** count, so two transactions prepared back
to back do not both claim the same one.

A contract creation cannot have its gas estimated — there is no address to call
— so it has to say its own, and raises `Incomplete` if it does not.

## Signing a message

No prompt, no wallet, no round trip:

```moonbit
async fn login_signature(
  node : @http.HttpProvider[@endpoint.Endpoint],
  account : @local.LocalAccount,
) -> @endor.Hex raise {
  let client = @wallet.WalletClient::new(node, account)
  client.sign_message("login to example.com")
}
```

The result is the same 65 bytes a wallet would answer with — `r ‖ s ‖ v`, with
`v` as 27 or 28 — over the same EIP-191 prefixed digest. A verifier cannot tell
which produced it, which is the whole point.

`sign_typed_data` is the same shape over an `@endor.TypedData`.

## Determinism

The nonce a signature needs is derived from the key and the digest by RFC 6979,
not drawn from a random source. Signing the same digest with the same key twice
gives the same bytes — a property worth relying on in tests, and the reason a
weak random source cannot leak the key here.

## Errors

Two error types meet in a client, and `@endor.WalletError` keeps whichever one
happened whole rather than flattening it to a string:

```moonbit
async fn pay_reporting(
  node : @http.HttpProvider[@endpoint.Endpoint],
  account : @local.LocalAccount,
  to : @endor.Address,
) -> Unit {
  let client = @wallet.WalletClient::new(node, account)
  // parsed outside, so the block below catches only the client's errors
  let value = @endor.Wei::from_ether("0.01") catch {
    _ => return println("that is not an amount")
  }
  try {
    let hash = client.send(to~, value~)
    println("broadcast as \{hash}")
  } catch {
    @wallet.Provider(e) =>
      println("the node said no: \{e.message()}, retryable=\{e.is_retryable()}")
    @wallet.Account(e) => println("could not sign: \{e.message()}")
    @wallet.Incomplete(what) => println("missing: \{what}")
  }
}
```

Match on the inner error when it matters — `Provider(UserRejected)` is a user
declining a prompt, which only a wallet-backed account can produce.

## Next

- [Send ETH](/cookbook/send-eth/) — the same client with a wallet in front of it
- [Sign a message](/cookbook/sign/) — what a wallet shows the user, and why
- [Signing](/reference/signing/) — the whole surface
