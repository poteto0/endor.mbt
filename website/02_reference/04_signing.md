---
title: Signing
description: personal_sign and eth_signTypedData_v4, and what TypedData refuses to build.
---

# Signing

| Function                                        | JSON-RPC method        | Returns      |
| ----------------------------------------------- | ---------------------- | ------------ |
| `@provider.sign_message(p, who, message)`       | `personal_sign`        | `@endor.Hex` |
| `@provider.sign_message_bytes(p, who, hex)`     | `personal_sign`        | `@endor.Hex` |
| `@provider.sign_typed_data(p, who, doc)`        | `eth_signTypedData_v4` | `@endor.Hex` |

These prompt the user — signing is the wallet's job, and the key never leaves it —
so they raise `UserRejected` (4001) when they decline and `Unauthorized` (4100)
for an account the dapp was never authorized for. The answer is the signature as
raw `Hex`, 65 bytes of `r ‖ s ‖ v`; the SDK does not recover the signer from it.

`sign_message` takes text and puts its UTF-8 bytes on the wire.
`sign_message_bytes` takes the bytes directly, for a nonce or a hash that was
never a string — the wallet shows those as hex, so prefer the first wherever
the message really is text.

## Or with the key in this process

A wallet is not the only thing that can sign. `@local.LocalAccount` holds a
private key and signs locally, and `@wallet.WalletClient` pairs either kind of
account with a transport so the calling code does not change:

| Call                            | With a wallet account         | With a local key                     |
| ------------------------------- | ----------------------------- | ------------------------------------ |
| `client.sign_message(text)`     | `personal_sign`, one prompt   | signed here, no round trip           |
| `client.sign_typed_data(doc)`   | `eth_signTypedData_v4`        | signed here, no round trip           |
| `client.send(to~, value~)`      | `eth_sendTransaction`         | signed here, `eth_sendRawTransaction`|

Both produce the same 65 bytes over the same digest, and `v` is 27 or 28 either
way; a verifier cannot tell them apart. The recipe is
[Sign with a local key](../../cookbook/local-account/).

An account is asynchronous even when it holds its own key, because one that
does not has to ask and wait. `@local.LocalAccount` simply never awaits.

## personal_sign

```moonbit
async fn sign_text(
  wallet : @browser.BrowserProvider,
  who : @endor.Address,
) -> @endor.Hex raise {
  @provider.sign_message(wallet, who, "login to example.com")
}
```

EIP-191 personal signing: the wallet prefixes the message with
`"\x19Ethereum Signed Message:\n" + length` before hashing it, which is what
keeps a signature produced this way from ever being a valid transaction. The
message goes over the wire as its UTF-8 bytes in hex (`@endor.Hex::from_utf8`,
public for a caller who needs it), so the wallet can show the user the text they
are signing.

Note the parameter order EIP-191 fixed: the message comes first and the address
second — the opposite way round from the typed-data call, which is why both are
wrapped rather than left to `Provider::request`.

## eth_signTypedData_v4

`sign_typed_data` takes an `@endor.TypedData`: the
`{ types, primaryType, domain, message }` document as a validated value rather
than as raw `Json`. The wallet receives it serialized, since v4 takes the
document as a string rather than as a nested object. A wallet that does not
implement the method at all answers `UnsupportedMethod` (4200).

```moonbit
fn build_permit(
  token : @endor.Address,
  holder : @endor.Address,
) -> @endor.TypedData raise @endor.CodecError {
  @endor.TypedData::new(
    @endor.TypedDataDomain::new(
      name="Endor",
      version="1",
      chain_id=@endor.ChainId::mainnet(),
      verifying_contract=token,
    ),
    primary_type="Permit",
    types={
      "Permit": [
        @endor.TypedDataField::new("holder", "address"),
        @endor.TypedDataField::new("value", "uint256"),
      ],
    },
    message={ "holder": holder.to_json(), "value": "1000000000000000000" },
  )
}
```

## What building it checks

Building the document is what validates it, so a document a wallet would reject
is refused here — where the error can name the field — rather than coming back as
an opaque wallet-side failure:

- `primaryType` has to be one of the declared types
- every type a field refers to has to be elementary (`address`, `bool`, `string`,
  `bytes`, `bytes1`…`bytes32`, `uint8`…`uint256`, `int8`…`int256`, and arrays of
  those) or a struct the document defines
- the message has to match the type it claims to be, member for member: a
  declared member that is missing is an error, and so is one no type declares —
  the latter would not be signed, so carrying it means believing something the
  signature will not say
- a value has to fit its declared type: an `address` that is not 20 bytes, a
  `bytes32` that is not 32, a `uint8` of 256 are all refused. A `uint256` past
  `2^53` has to be carried as a decimal (or `0x`) **string**, because a JSON
  number has already lost precision by then — passing one is an error rather than
  a signature over a value the caller did not write

`EIP712Domain` is **derived** from `@endor.TypedDataDomain` and must not be
declared in `types`: only the domain fields actually present take part in the
domain separator, and the entry is generated in EIP-712's own field order, so the
type and the value cannot disagree.

The message stays `Json`, because a value is only meaningful against the type it
is declared as, and that declaration lives in `types` — checking the two against
each other is what `TypedData::new` does.

## The digest

Where the digest is computed follows the key. Ask a **wallet** to sign and the
wallet hashes: the calls above hand over the message or the document, not a
hash. Sign with `@local.LocalAccount` and the SDK hashes — EIP-191 through
`endor/eips/eip191`, EIP-712 through `endor/eips/eip712`, a transaction through
`UnsignedTransaction::signing_digest`.

Both hashing paths are `endor/eips/eip712`'s — `encodeType`, `typeHash`,
`encodeData`, `hashStruct`, `domainSeparator`, `digest` — and they are public
for a caller who needs the digest itself, EIP-1271 being the case that does.

## Documents a standard already fixed

The document above is written by hand, and its `Permit` is a made-up type that
happens to share a name with a real one. When a standard fixes the document, the
SDK builds it, and each answers with the same `@endor.TypedData` this page signs:

| Package              | Document                                                | Recipe                                                      |
| -------------------- | ------------------------------------------------------- | ----------------------------------------------------------- |
| `endor/eips/eip3009` | the transfer a holder signs and somebody else submits    | [Transfer without gas](../../cookbook/gasless-transfer/)     |
| `endor/eips/eip2612` | `Permit` — the real one: an ERC-20 approval, signed      | [Approve without a transaction](../../cookbook/permit/)      |

Reach for one of those before writing the document by hand. A standard's
document is fixed member for member, and a member misspelled or reordered
produces a signature that verifies as nothing.
