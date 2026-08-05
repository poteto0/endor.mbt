---
title: Approve without a transaction
description: EIP-2612 permit — the ERC-20 approval, signed instead of sent.
---

# Approve without a transaction

Spending a user's tokens from a contract takes two transactions: `approve`, and
then the call that actually pulls them. Two prompts, two fees, and a first one
that visibly does nothing.

[EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) replaces the first with a
**signature**. The owner signs a `Permit`; the spender submits `permit(...)` and
its own call together, as one transaction. The user sees one prompt, pays for
one transaction, and the approval and the spend can no longer come apart. USDC
carries it, and so does almost every token written since.

As with [Transfer without gas](../gasless-transfer/), what is signed is an
EIP-712 document — so this is [Sign a message](../sign/) with the document fixed
by the standard rather than written by you.

<div class="alert alert--note" role="note">
  <div class="alert__title">No demo on this page</div>
  <div class="alert__description">

The other half needs a *spender* — a contract that takes the signature and calls
`permit` before pulling the tokens — and this site has none to point at. The
SDK's side of that, an ERC-20 preset that sends `permit`, is
[#73](https://github.com/poteto0/endor.mbt/issues/73).

  </div>
</div>

## The two things only the token can tell you

`eips/eip2612` builds documents and calls no contract. But unlike EIP-3009, a
permit cannot be assembled from what the caller already knows: the nonce is the
token's, and so is the domain. Both are read through the ERC-20 preset and
passed in.

```moonbit
async fn[P : @provider.Provider] permit_domain(
  p : P,
  token : @endor.Address,
  chain : @endor.ChainId,
) -> @endor.TypedDataDomain raise {
  let preset = @erc20.Erc20::new(token)
  let domain = @eip2612.domain(
    // exactly what `name()` answers — so read it rather than typing it
    name=preset.name(p),
    // "1" for most tokens and the default, but USDC says "2". This is the
    // single most common way a permit signature comes out unusable
    version="2",
    chain_id=chain,
    token~,
  )
  // and this is how you find out you guessed wrong, before the user signs
  domain.check_separator(on_chain=preset.domain_separator(p))
  domain
}
```

`DOMAIN_SEPARATOR()` is the hash the token itself verifies signatures against,
and `check_separator` compares it with the hash of the domain you built. It
cannot tell you *what* to fix — a hash is a hash — but it catches the whole
family of mistakes that are otherwise invisible until the chain rejects the
transaction: the wrong `version`, a `name` that is off by a character, the wrong
chain, a token that binds a `salt` instead of a chain id.

**Build the domain once and keep it.** Neither `name()` nor `DOMAIN_SEPARATOR()`
can change for a given token on a given chain, so those two `eth_call`s belong
to setting the token up rather than to each signature. Only the nonce has to be
re-read per permit.

## The permit

Five members, and the nonce is a **counter** rather than the 32 random bytes an
EIP-3009 authorization carries:

```moonbit
async fn[P : @provider.Provider] approve_one_dollar(
  p : P,
  token : @endor.Address,
  owner : @endor.Address,
  spender : @endor.Address,
  now : BigInt,
) -> @eip2612.Permit raise {
  @eip2612.Permit::new(
    owner~,
    spender~,
    // USDC has 6 decimals — one dollar, in the token's smallest unit
    value=1000000,
    // read afresh for every signature: the token bumps it as each permit is used
    nonce=@erc20.Erc20::new(token).nonces(p, owner),
    // good for twenty minutes
    deadline=now + 1200,
  )
}
```

Because the nonce is a counter, **only one permit per owner can be in flight**.
Sign two against the same nonce and they are the same permit: whichever is
submitted first works, and the other is dead. That is the opposite of EIP-3009,
where random nonces let any number be outstanding at once.

`deadline` has no default. `type(uint256).max` is the standard's way of spelling
"never expires", and passing it says that was meant — an approval a stranger may
still submit next year is worth having to write out.

## Signing it

```moonbit
async fn sign_permit(
  wallet : @browser.BrowserProvider,
  permit : @eip2612.Permit,
  domain : @endor.TypedDataDomain,
) -> Unit raise @endor.CodecError {
  // building the document is what validates it, and it raises on its own —
  // keep it out of the `try` so the wallet's own failures stay matchable
  let document = permit.typed_data(domain)
  try {
    let signature = @provider.sign_typed_data(wallet, permit.owner(), document)
    // hand these to the spender: the permit says what was approved, the
    // signature says who approved it
    println("permit: \{document.to_json().stringify()}")
    println("signature: \{signature}")
  } catch {
    // the same failures as any other prompt — see [Sign a message](../sign/)
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

Nothing was broadcast and nothing was spent. The allowance does not exist yet:
it appears the moment somebody submits `permit(owner, spender, value, deadline,
v, r, s)`, and note what is *not* an argument there — the nonce. The token reads
its own, which is why a stale one fails.

## DAI is not this

DAI's permit came before the standard and takes different members —
`(holder, spender, nonce, expiry, allowed)`, granting all-or-nothing rather than
an amount. The type name and its members are both in the hash, so a document
built here is not a signature DAI accepts, and `check_separator` **will not catch
it**: DAI's domain is an ordinary EIP-712 domain and matches fine.

If you may be handed either kind of token, compare the token's own
`PERMIT_TYPEHASH` against what this package would sign:

```moonbit
fn is_standard_permit(document : @endor.TypedData, on_chain : @endor.Hex) -> Bool raise {
  document.type_hash("Permit") == on_chain
}
```

The standard's is
`0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9` — the hash
of `Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)`,
and the constant every EIP-2612 token declares. Building DAI's own document is
not in the SDK.

## Permit, or transfer without gas?

Both are a signature that moves value without the signer sending a transaction.
They are not interchangeable:

| | **EIP-2612 permit** | [EIP-3009](./gasless-transfer/) |
| --- | --- | --- |
| What it authorizes | an **allowance** somebody may draw on | one **transfer**, fixed in the signature |
| The nonce | a counter, read from the token | 32 random bytes, drawn by you |
| In flight at once | one per owner | as many as you like |
| Who submits | the spender, alongside its own call | anyone |
| Token support | most tokens written since 2020 | regulated stablecoins — USDC, JPYC |

Reach for permit when a contract needs to pull tokens as part of doing something
else. Reach for EIP-3009 when the transfer *is* the point and the holder has no
ether to send it with.
