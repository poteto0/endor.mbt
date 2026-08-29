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
fn delegate_to(
  contract : @endor.Address,
  authority_key : @endor.Hex,
  authority_nonce : UInt64,
) -> @endor.SignedAuthorization raise {
  let authorization = @endor.Authorization::new(
    chain_id=@endor.ChainId::mainnet(),
    address=contract,
    nonce=@endor.Quantity::new(authority_nonce),
  )
  let key = @secp256k1.PrivateKey::from_bytes(authority_key.to_bytes())
  let signature = key.sign(authorization.signing_digest())
  authorization.signed(
    r=signature.r(),
    s=signature.s(),
    y_parity=signature.recovery_id(),
  )
}
```

`signing_digest` is `keccak256(0x05 || rlp([chain_id, address, nonce]))`. The
`0x05` is not a transaction type — it is there so that an authorization can
never be read as one.

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

```moonbit
async fn self_sponsored_nonce(
  node : @http.HttpProvider[@endpoint.Endpoint],
  authority : @endor.Address,
) -> UInt64 raise {
  // the pending count is the nonce this transaction will take, so the
  // authorization inside it is signed for the one after
  @provider.transaction_count(node, authority, block=Pending) + 1
}
```

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

The same nine fields an EIP-1559 transaction has, plus the list:

```moonbit
async fn send_delegation(
  node : @http.HttpProvider[@endpoint.Endpoint],
  sponsor : @local.LocalAccount,
  authorizations : Array[@endor.SignedAuthorization],
) -> @endor.TxHash raise {
  let client = @wallet.WalletClient::new(node, sponsor)
  let from = sponsor.address()
  let tx = @endor.UnsignedTransaction::eip7702(
    chain_id=@provider.chain_id(node),
    nonce=@endor.Quantity::new(
      @provider.transaction_count(node, from, block=Pending),
    ),
    max_priority_fee_per_gas=@endor.Wei::from_gwei("1"),
    max_fee_per_gas=@endor.Wei::from_gwei("20"),
    gas=@endor.Quantity::new(200000),
    to=from,
    authorization_list=authorizations,
  )
  client.send_transaction(tx)
}
```

Two things the constructor will not let you get wrong:

- **`to` is required.** A 7702 transaction cannot create a contract, so the
  field is an `Address` rather than an `Address?`. There is no argument to omit.
- **The list cannot be empty.** A 7702 transaction that delegates nothing is
  invalid, so `eip7702` raises rather than building one. The list is copied in,
  so emptying yours afterwards changes nothing.

`prepare` does not build this shape — it fills in an EIP-1559 transaction — so
the chain id, the nonce and the gas are read and passed here.

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

## Only a key can send one, for now

`send_transaction` above works because a `LocalAccount` signs the bytes itself
and they leave as `eth_sendRawTransaction`.

A wallet-held account takes the other path: the whole transaction is handed over
as `eth_sendTransaction`, and that request has no field for an authorization
list. Sending it without one would send a *different* transaction, so
`to_request` answers `None` rather than quietly dropping it:

```moonbit
fn has_request_form(
  tx : @endor.UnsignedTransaction,
  from : @endor.Address,
) -> Bool {
  tx.to_request(from~) is Some(_)
}
```

Through a `WalletClient` that is a `WalletError::Incomplete`.

That is also why this page has no live demo: there is no wallet path to drive,
and the demos on this site never hold a key.

## Revoking

A delegation is undone by delegating to the zero address. It is an ordinary
authorization — same fields, same signature, one more nonce:

```moonbit
fn revoke(
  authority_key : @endor.Hex,
  authority_nonce : UInt64,
) -> @endor.SignedAuthorization raise {
  delegate_to(
    @endor.Address::from_string("0x0000000000000000000000000000000000000000"),
    authority_key,
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
