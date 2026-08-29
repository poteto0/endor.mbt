---
title: Delegate an EOA (EIP-7702)
description: An account that runs a contract's code — the authorization is signed apart from the transaction that carries it.
---

# Delegate an EOA

An EOA can point at a contract and run its code as its own. That is
[EIP-7702](https://eips.ethereum.org/EIPS/eip-7702): a transaction of type
`0x04` carries a list of **authorizations**, and each one puts one account's
delegation on chain. Afterwards the account has code — batching, a session key,
a sponsor paying its gas — while still being the account it was.

The part worth holding on to is that an authorization is signed **apart from
the transaction**. The account that delegates and the account that pays are two
different signatures, and they need not be the same person.

## The authorization

Three fields, signed under a magic byte of their own:

```moonbit
async fn delegate_to(
  authority : @local.LocalAccount,
  contract : @endor.Address,
  authority_nonce : UInt64,
) -> @endor.SignedAuthorization raise {
  authority.sign_authorization(
    @endor.Authorization::new(
      chain_id=@endor.ChainId::mainnet(),
      address=contract,
      nonce=@endor.Quantity::new(authority_nonce),
    ),
  )
}
```

`sign_authorization` is the fourth thing an `Account` signs, alongside a
transaction, a message and a typed-data document. It answers with a
`SignedAuthorization` rather than the 65 bytes the other three give back: what a
transaction carries is the six-element tuple, and recovering the authority needs
the parity bit kept.

Underneath it is `signing_digest`, which is
`keccak256(0x05 || rlp([chain_id, address, nonce]))` — public for a caller
holding a key some other way. The `0x05` is not a transaction type; it is there
so that an authorization can never be read as one.

## The nonce is the authority's

This is the one that costs an afternoon. `nonce` is the **delegating account's**
own nonce, not the transaction's. Get it wrong and nothing raises: the
authorization is simply skipped when the block is built, the transaction
succeeds, and the account has no code.

Two cases, and they differ by one:

| Who pays | The authorization's nonce |
| -------- | ------------------------- |
| someone else | the authority's current nonce |
| the authority itself | its current nonce **+ 1** — the transaction consumes one first |

`WalletClient::nonces` is that arithmetic, and it answers with both numbers
because they are one answer: read separately they would be two questions about
a number that moves.

```moonbit
async fn delegation_nonces(
  client : @wallet.WalletClient[
    @http.HttpProvider[@endpoint.Endpoint],
    @local.LocalAccount,
  ],
) -> (@endor.Quantity, @endor.Quantity) raise {
  // the account is delegating in its own transaction
  let mine = client.nonces(SelfSponsored)
  // and here it is paying for somebody else's
  let theirs = client.nonces(
    Sponsored(
      @endor.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
    ),
  )
  (mine.authorization, theirs.authorization)
}
```

Which of the two it is has to be **said**. The SDK does not work it out from
whether the authority happens to be the account signing the transaction —
that guess is right until the day somebody sponsors themselves through a second
client, and the failure it produces is invisible. Naming this client's own
account as `Sponsored` is refused rather than answered one short.

## Every chain at once

Chain id `0` means the authorization is valid on **every** chain, at that nonce.
It is the form a wallet uses to delegate once across a user's chains, and it is
also a signature anyone can replay onto a chain you were not thinking about.

```moonbit
fn delegate_everywhere(
  contract : @endor.Address,
  authority_nonce : UInt64,
) -> @endor.Authorization {
  @endor.Authorization::any_chain(
    address=contract,
    nonce=@endor.Quantity::new(authority_nonce),
  )
}
```

<div class="alert alert--warning" role="note">
  <div class="alert__title">Chain 0 has to be asked for by name</div>
  <div class="alert__description">

`Authorization::new` raises on chain id `0` rather than accepting it, so an
every-chain authorization cannot arrive through a variable that happened to be
zero. `any_chain` takes no chain id at all: it is the only way to spell it, and
it says what it does at the call site.

  </div>
</div>

## The transaction

The same nine fields an EIP-1559 transaction has, plus the list. Hand the list
to `prepare` and it builds the `0x04` envelope instead of the `0x02` one:

```moonbit
async fn send_delegation(
  node : @http.HttpProvider[@endpoint.Endpoint],
  sponsor : @local.LocalAccount,
  authorizations : Array[@endor.SignedAuthorization],
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::new(node, sponsor)
  let nonces = client.nonces(SelfSponsored)
  let tx = client.prepare(
    to=sponsor.address(),
    nonce=nonces.transaction,
    gas=@endor.Quantity::new(200000),
    authorization_list=authorizations,
  )
  client.send_transaction(tx)
}
```

`nonce` is passed rather than left open, so the transaction takes the nonce the
authorizations were signed against. The chain id and the fee are still read from
the node.

Two things `prepare` asks for that it fills in for every other transaction:

- **`to`.** A 7702 transaction delegates; it does not create. The type says so
  too — `UnsignedTransaction::eip7702` takes an `Address`, not an `Address?`.
- **`gas`.** `eth_estimateGas` is never told the authorization list, so what it
  answers prices the delegations at nothing. Rather than send a transaction that
  runs out of gas, `prepare` raises `Incomplete` and asks.

A flat `gasPrice` is refused for the same reason there is no legacy 7702
envelope: there is nowhere to put it.

And one thing the constructor underneath will not let you get wrong: **the list
cannot be empty.** A 7702 transaction that delegates nothing is invalid, so
`eip7702` raises rather than building one. The list is copied in, so emptying
yours afterwards changes nothing.

## Which account it delegates

Nothing in an authorization names the account it is for. The authority is the
one that signed, so it comes back out of the signature and nowhere else:

```moonbit
fn delegates(
  authorization : @endor.SignedAuthorization,
  expected : @endor.Address,
) -> Bool raise {
  authorization.authority() == expected
}
```

Recovery is not verification: it answers with whoever signed those bytes,
whether or not that is who you meant. So a sponsor handed a list of
authorizations to pay for checks it here — an authorization delegates the
account that signed it, and nothing else in it says so.

What this does *not* catch is the nonce. A wrong one is a valid signature by the
right account; it is the chain that skips it when the block is built.

## On the wire

An authorization travels as a six-field JSON object — the three signed fields,
then `yParity`, `r` and `s` — inside a transaction's `authorizationList` and
inside what a node answers back:

```moonbit
fn read_authorizations(
  entries : Array[Json],
) -> Array[@endor.SignedAuthorization] raise {
  entries.map(@endor.SignedAuthorization::from_json)
}
```

`to_json` is the same object in the other direction. `r` and `s` go out as full
32-byte words and are read back either way, since a node is free to trim their
leading zeros.

## Through a wallet

`send_transaction` above works because a `LocalAccount` signs the bytes itself
and they leave as `eth_sendRawTransaction`.

A wallet-held account takes the other path: the whole transaction is handed over
as `eth_sendTransaction`. That request carries an `authorizationList`, which is
a field no other envelope has, so the wallet knows to build a `0x04` — and
`to_request` answers with it rather than `None`:

```moonbit
fn has_request_form(
  tx : @endor.UnsignedTransaction,
  from : @endor.Address,
) -> Bool {
  tx.to_request(from~) is Some(_)
}
```

What does not change is the nonce. Everywhere else, a wallet is left to pick
one; here it cannot be, because the authorizations were signed against a
particular one before the request existed. So a delegation goes out through
`nonces` and `prepare` and never through `send`, whichever account is behind it.

This page has no live demo all the same: the demos on this site drive whatever
wallet the reader has, and one that does not implement EIP-7702 would take the
request and delegate nobody.

What a wallet-held account cannot do is sign the **authorization**: there is no
standard RPC for one and no EIP-1193 method either, so `sign_authorization`
raises `NotSupported` on a `JsonRpcAccount`. A wallet can pay for a delegation
and send it; the delegation itself is signed where the key is.

## Revoking

A delegation is undone by delegating to the zero address. It is an ordinary
authorization — same fields, same signature, one more nonce:

```moonbit
async fn revoke(
  authority : @local.LocalAccount,
  authority_nonce : UInt64,
) -> @endor.SignedAuthorization raise {
  delegate_to(
    authority,
    @endor.Address::from_string("0x0000000000000000000000000000000000000000"),
    authority_nonce,
  )
}
```

Nothing else clears it: the account keeps the code until it says otherwise, and
that survives the transaction that set it.

## Next

- [Sign with a local key](/cookbook/local-account/) — the account that can send one
- [Signing](/reference/signing/) — the digests, and what each one commits to
- [Writes](/reference/writes/) — the transaction types, and which fee goes with which
