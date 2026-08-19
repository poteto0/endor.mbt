---
title: Move a stablecoin
description: The submitter's half of EIP-3009 — a preset that sends what the holder signed, with JPYC as the example.
---

# Move a stablecoin

[Transfer without gas](../gasless-transfer/) is the holder's half: they sign an
authorization and pay nothing. This page is the other half — **submitting** it.
Someone has to send the transaction and pay for it, and `contract/stablecoin` is
the preset that does.

It is [Read an ERC-20](../erc20/) with the two extensions that make a token a
stablecoin: [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009), which lets a
holder sign a transfer for somebody else to submit, and
[EIP-2612](https://eips.ethereum.org/EIPS/eip-2612), which does the same for an
approval. JPYC, USDC and most other regulated stablecoins carry both.

<div class="alert alert--note" role="note">
  <div class="alert__title">No demo on this page</div>
  <div class="alert__description">

The demos on this site drive your wallet. Submitting is the half a wallet does
_not_ do: it needs an account holding gas and willing to spend it on somebody
else's transfer, which is a service, not a browser extension.

  </div>
</div>

## The token

`Stablecoin::new` takes the address. A stablecoin *is* an ERC-20, so everything
a plain token can do it does too — `balance_of`, `transfer`, `approve`,
`decimals` and the rest are on it directly:

```moonbit
fn jpyc() -> @stablecoin.Stablecoin raise @endor.CodecError {
  @stablecoin.Stablecoin::new(
    @endor.Address::from_string("0x431D5dfF03120AFA4bDf332c61A6e1766eF37BDB"),
  )
}

async fn[P : @provider.Provider] balance(
  p : P,
  who : @endor.Address,
) -> BigInt raise {
  jpyc().balance_of(p, who)
}
```

Amounts are in the token's own smallest unit, as everywhere else in this SDK.
JPYC has 18 decimals and USDC has 6, so `decimals()` is a read, never an
assumption.

`token()` hands out the same token as an `@erc20.Erc20`, for passing to
something that takes one. The `Transfer` log helpers stay there:
`transfer_topic()` and `decode_transfer(log)` take no token, so there is nothing
for a preset to delegate.

## The domain, read off the token

A signature is bound to one token on one chain, and a domain that is not the
token's own fails _silently_: the document signs and displays perfectly well,
and is rejected on chain afterwards. So don't spell it — ask:

```moonbit
async fn[P : @provider.Provider] domain(
  p : P,
) -> @endor.TypedDataDomain raise {
  jpyc().domain(p)
}
```

That reads `name()`, `version()` and the chain, builds the domain, and then
hands it to the token's own `DOMAIN_SEPARATOR()` — which is the token saying yes
or no to the whole thing at once, before anybody is asked to sign. A token
without `version()` is answered as `"1"`, the guess that is right almost
everywhere, and the separator check is what confirms or refuses it.

Pass `chain_id=` to build a domain for a chain you are not connected to. Signing
is then exactly [Transfer without gas](../gasless-transfer/).

## Submitting what was signed

The relayer holds two things: the authorization, which says what was agreed, and
the signature, which says who agreed to it. `submitter` is who pays — never the
account whose units move:

```moonbit
async fn[P : @provider.Provider] relay(
  p : P,
  relayer : @endor.Address,
  authorization : @eip3009.Authorization,
  signature : @endor.Hex,
) -> @endor.TxHash raise {
  jpyc().transfer_with_authorization(p, submitter=relayer, authorization~, signature~)
}
```

The hash is the transaction's, not the transfer's verdict: whether the token
took it is in the receipt, and `@erc20.Erc20::decode_transfer` reads the
`Transfer` log out of it — [Wait for a receipt](../receipts/).

`receive_with_authorization` is the same call for the document built by
`receive_typed_data`, and the token requires its submitter to be the recipient.
The two are not interchangeable in either direction: the name is in the hash.

## Before paying for it

A nonce is good once. Signed twice, submitted twice, or cancelled in between —
the token marks it either way, and a transaction against a spent nonce reverts
after the gas is spent:

```moonbit
async fn[P : @provider.Provider] worth_submitting(
  p : P,
  authorization : @eip3009.Authorization,
) -> Bool raise {
  let token = jpyc()
  !token.authorization_state(
    p,
    authorizer=authorization.from(),
    nonce=authorization.nonce(),
  )
}
```

It is a read, so it costs nothing and prompts nobody. It is also not a
guarantee: the answer is true until somebody else's transaction lands first.

## Taking one back

Cancelling burns the nonce, which is what makes what was signed against it
un-submittable. Only the account that signed the authorization may sign the
cancellation — and unlike the transfer, this transaction is one the holder
themselves usually pays for:

```moonbit
async fn cancel(
  wallet : @browser.BrowserProvider,
  holder : @endor.Address,
  nonce : @endor.Hex,
) -> @endor.TxHash raise {
  let token = jpyc()
  let cancellation = @eip3009.CancelAuthorization::new(authorizer=holder, nonce~)
  let signature = @provider.sign_typed_data(
    wallet,
    holder,
    cancellation.typed_data(token.domain(wallet)),
  )
  token.cancel_authorization(wallet, submitter=holder, cancellation~, signature~)
}
```

A domain is fixed for one token on one chain, and reading it is four calls. The
example reads it inline to stay one function; a service submitting more than one
of these should read it once and keep it.

## Approving without a transaction

EIP-2612 is the same trade for an allowance, and its submitter is normally the
spender: the owner signs, and the spender raises the allowance and spends it in
one transaction of their own. [Approve without a transaction](../permit/) builds
the document; this sends it:

```moonbit
async fn[P : @provider.Provider] use_permit(
  p : P,
  spender : @endor.Address,
  permit : @eip2612.Permit,
  signature : @endor.Hex,
) -> @endor.TxHash raise {
  jpyc().permit(p, submitter=spender, permit~, signature~)
}
```

The `nonce` a permit is signed against is a counter — `@erc20.Erc20::nonces` —
and this call moves it, so a second permit signed against the same one is
worthless. That is the opposite of EIP-3009's nonce, which is 32 random bytes
and lets several authorizations be in flight at once.

## When the signer is a contract

A smart contract wallet — Safe and the rest — has no private key, so what it
answers is not a 65-byte `(v, r, s)`, and every call above refuses it before
sending anything. FiatTokenV2_2, what USDC runs today, gave each of the four
calls a second selector that takes the signature as `bytes` and asks the signing
contract itself whether it is good
([EIP-1271](https://eips.ethereum.org/EIPS/eip-1271)). Those are the `_1271`
methods:

```moonbit
async fn[P : @provider.Provider] relay_from_a_safe(
  p : P,
  relayer : @endor.Address,
  authorization : @eip3009.Authorization,
  signature : @endor.Hex,
) -> @endor.TxHash raise {
  jpyc().transfer_with_authorization_1271(
    p, submitter=relayer, authorization~, signature~,
  )
}
```

`receive_with_authorization_1271`, `cancel_authorization_1271` and `permit_1271`
are the other three. Everything before the signature is identical; only its type
on the wire changes.

Which form to send is yours to say, not something the SDK guesses from a length:
**a token older than V2_2 does not carry these selectors at all**, and the call
reverts. An EOA's 65 bytes go through either form, so the plain methods stay the
safe default and `_1271` is what you reach for when the signer is a contract —
or when you know the token is V2_2 and would rather let it do the unpacking.

## A signature that cannot work is refused here

The four plain calls end in the same `(v, r, s)`, split out of the 65 bytes a wallet
answers with. Anything that is not a signature — the wrong length, an `s` in the
high half that the token's `ecrecover` would reject — raises before a
transaction exists, rather than costing gas to fail on chain. A `v` of `0` or
`1`, which is how a typed transaction spells it, is read as the `27` or `28` the
token wants.
