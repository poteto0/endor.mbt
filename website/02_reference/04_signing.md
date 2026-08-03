---
title: Signing
description: personal_sign and eth_signTypedData_v4, and what TypedData refuses to build.
---

# Signing

| Function                                  | JSON-RPC method        | Returns      |
| ----------------------------------------- | ---------------------- | ------------ |
| `@provider.sign_message(p, who, message)` | `personal_sign`        | `@endor.Hex` |
| `@provider.sign_typed_data(p, who, doc)`  | `eth_signTypedData_v4` | `@endor.Hex` |

Both prompt the user — signing is the wallet's job, and the key never leaves it —
so both raise `UserRejected` (4001) when they decline and `Unauthorized` (4100)
for an account the dapp was never authorized for. The answer is the signature as
raw `Hex`, 65 bytes of `r ‖ s ‖ v`; the SDK does not recover the signer from it.

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

Nothing is hashed locally: the **wallet** computes the digest, which is why
signing needs no keccak256 here even though `crypto/` has it.

`endor/eips/eip712` does implement the EIP-712 hashing — `encodeType`, `typeHash`,
`encodeData`, `hashStruct`, `domainSeparator`, `digest` — for the callers that
need the digest itself. Wiring it into signing is
[#45](https://github.com/poteto0/endor.mbt/issues/45), and the thing that will
need it is EIP-1271, not this.
