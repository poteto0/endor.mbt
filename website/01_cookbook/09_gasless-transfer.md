---
title: Transfer without gas
description: EIP-3009 — the holder signs the transfer, somebody else pays to submit it.
---

# Transfer without gas

A wallet holding nothing but stablecoins cannot move them: every transfer is a
transaction, and a transaction costs the chain's own currency.
[EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) is how USDC, JPYC and most
other regulated stablecoins get around that. The holder **signs** what should
happen; anybody at all may then **submit** it and pay the gas.

What is signed is an EIP-712 document, so this is [Sign a message](../sign/) with
the document fixed by the standard rather than written by you — which is exactly
what `eips/eip3009` builds.

<div class="alert alert--note" role="note">
  <div class="alert__title">No demo on this page</div>
  <div class="alert__description">

Every other recipe here carries a widget you can click. This one does not: a
signature is only half of an EIP-3009 transfer, and the other half needs a
*submitter* — a service holding gas, willing to relay yours. This site has none.
The SDK's side of the submission, an ERC-20 preset that sends
`transferWithAuthorization`, is
[#73](https://github.com/poteto0/endor.mbt/issues/73).

  </div>
</div>

## The domain is the token's

An EIP-3009 signature is bound to one token on one chain, and getting that wrong
fails silently: the document signs and displays perfectly well, and is then
rejected on chain. `@eip3009.domain` fixes the three fields the standard fixes
and leaves you the one it cannot — `name`, which must match the token's own
`name()` byte for byte:

```moonbit
fn jpyc(chain : @endor.ChainId) -> @eip712.TypedDataDomain raise @endor.CodecError {
  @eip3009.domain(
    // exactly what `name()` answers — not what the token is called in prose
    name="JPY Coin",
    // "1" for almost every token, and the default; read it off the contract's
    // `version()` or `EIP712_VERSION` when it has one
    version="1",
    chain_id=chain,
    token=@endor.Address::from_string(
      "0x431D5dfF03120AFA4bDf332c61A6e1766eF37BDB",
    ),
  )
}
```

## The authorization

Six members: who, to whom, how much, the window it is good for, and the nonce
that makes it usable once.

```moonbit
fn pay(
  from : @endor.Address,
  to : @endor.Address,
  now : BigInt,
  nonce : @endor.Hex,
) -> @eip3009.Authorization raise @endor.CodecError {
  @eip3009.Authorization::new(
    from~,
    to~,
    // JPYC has 18 decimals — 1000 JPYC, in the token's smallest unit
    value=BigInt::from_string("1000000000000000000000"),
    // good for an hour. `valid_after` defaults to 0, meaning "from now"
    valid_before=now + 3600,
    nonce~,
  )
}
```

The `nonce` is **32 random bytes, not a counter**. It is what the token marks as
used, so two authorizations signed with the same nonce are the same
authorization and only the first submitted takes effect — and, because there is
no sequence to keep, several may be in flight at once. Drawing it is yours: the
SDK owns no randomness.

`valid_before` has no default on purpose. An authorization that never expires is
a signature somebody may hold and submit next year, so the window has to be
spelled. One that closes before it opens is refused where you wrote it, rather
than on chain.

## Signing it

`transfer_typed_data` turns the authorization into the document, and from there
it is an ordinary `sign_typed_data`:

```moonbit
async fn sign_transfer(
  wallet : @browser.BrowserProvider,
  from : @endor.Address,
  auth : @eip3009.Authorization,
  domain : @eip712.TypedDataDomain,
) -> Unit raise @endor.CodecError {
  // building the document is what validates it, and it raises on its own —
  // keep it out of the `try` so the wallet's own failures stay matchable
  let document = auth.transfer_typed_data(domain)
  try {
    let signature = @provider.sign_typed_data(wallet, from, document)
    // hand these two to whoever is submitting: the authorization says what was
    // agreed, the signature says who agreed to it
    println("authorization: \{document.to_json().stringify()}")
    println("signature: \{signature}")
  } catch {
    UserRejected => println("the user declined")
    UnsupportedMethod => println("this wallet cannot sign typed data")
    e => println("error: \{e}")
  }
}
```

Nothing was broadcast and nothing was spent. The signature is worth money to
whoever holds it, and travels like any other bearer token.

## Transfer, or receive?

Two forms, identical but for their name — and that name is in the hash, so a
signature for one is not a signature for the other.

| Form                        | Built by                | Who may submit it |
| --------------------------- | ----------------------- | ----------------- |
| `TransferWithAuthorization` | `transfer_typed_data`   | anyone            |
| `ReceiveWithAuthorization`  | `receive_typed_data`    | only `to`         |

Use the first unless the recipient is a contract that has to *react* to being
paid. For that case the second closes a real hole: with a plain transfer, a
stranger can land the payment on the contract out of band, ahead of the call
that was supposed to carry it, leaving that call to fail against a contract that
has already been paid. Requiring the submitter to be `to` makes the payment and
the reaction one transaction.

## Taking it back

An authorization is live until it is submitted or expires. `CancelAuthorization`
burns the nonce, which is what makes it un-submittable — it is a transaction of
its own, so this one does cost gas, and only the account that signed the
authorization may sign the cancellation:

```moonbit
async fn cancel(
  wallet : @browser.BrowserProvider,
  authorizer : @endor.Address,
  nonce : @endor.Hex,
  domain : @eip712.TypedDataDomain,
) -> @endor.Hex raise {
  let cancellation = @eip3009.CancelAuthorization::new(authorizer~, nonce~)
  @provider.sign_typed_data(wallet, authorizer, cancellation.typed_data(domain))
}
```

## What the submitter needs

The SDK does not send the transaction yet ([#73](https://github.com/poteto0/endor.mbt/issues/73)),
but everything it will need is readable off the authorization — the six members
`transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s)`
takes, less the signature, which is the wallet's answer:

```moonbit
fn call_arguments(auth : @eip3009.Authorization) -> Array[@abi.AbiValue] {
  [
    Address(auth.from()),
    Address(auth.to()),
    Uint(auth.value()),
    Uint(auth.valid_after()),
    Uint(auth.valid_before()),
    Bytes(auth.nonce().to_bytes()),
  ]
}
```

And if you are verifying rather than submitting, `digest()` is what the signature
was made over — the same hash the token recovers the signer from:

```moonbit
fn what_was_signed(
  auth : @eip3009.Authorization,
  domain : @eip712.TypedDataDomain,
) -> @endor.Hex raise @endor.CodecError {
  auth.transfer_typed_data(domain).digest()
}
```
