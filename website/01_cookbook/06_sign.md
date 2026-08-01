---
title: Sign a message
description: personal_sign for text, eth_signTypedData_v4 for a validated EIP-712 document.
islands:
  - sign
---

# Sign a message

Signing proves an account agreed to something without spending anything. The key
never leaves the wallet, so both calls below are prompts.

Costs nothing, broadcasts nothing, touches no chain — the only prompt on this
site that cannot spend anything:

<Island name="sign" trigger="load" />

## A plain message

```moonbit
async fn login(
  wallet : @browser.BrowserProvider,
  who : @endor.Address,
) -> Unit {
  try {
    // personal_sign — the wallet shows the text and signs it with `who`'s key
    let signature = @provider.sign_message(wallet, who, "login to example.com")
    println("signed as \{signature}")
  } catch {
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

The message is signed EIP-191 style: the wallet prefixes it with
`"\x19Ethereum Signed Message:\n" + length` before hashing, which is what keeps a
signature produced this way from ever being a valid transaction. It travels as
the UTF-8 bytes of the message in hex — that is what lets the wallet show the
user the text they are agreeing to — and the 65 bytes of `r ‖ s ‖ v` come back as
`Hex` for your backend to verify.

Note the argument order EIP-191 fixed: the message comes second here, and the
address second in the typed-data call below. The two are opposite ways round on
the wire, which is exactly why both are wrapped rather than left to
`Provider::request`.

## Typed data

`sign_typed_data` takes an `@endor.TypedData` — the
`{ types, primaryType, domain, message }` document as a validated value rather
than as raw `Json`:

```moonbit
fn permit(
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
        // a uint256 past 2^53 travels as a string, since a JSON number cannot
        // hold one without losing precision
        @endor.TypedDataField::new("value", "uint256"),
      ],
    },
    message={ "holder": holder.to_json(), "value": "1000000000000000000" },
  )
}
```

```moonbit
async fn sign_permit(
  wallet : @browser.BrowserProvider,
  who : @endor.Address,
  document : @endor.TypedData,
) -> Unit {
  try {
    let signature = @provider.sign_typed_data(wallet, who, document)
    println("signed: \{signature}")
  } catch {
    UserRejected => println("the user declined")
    // 4200 — the wallet does not implement eth_signTypedData_v4 at all
    UnsupportedMethod => println("this wallet cannot sign typed data")
    e => println("error: \{e}")
  }
}
```

## Building the document is what validates it

A document a wallet would reject is refused here, where the error can name the
field, rather than coming back as an opaque wallet-side failure:

- `primaryType` has to be one of the declared types
- every field type has to be elementary (`address`, `bool`, `string`, `bytes`,
  `bytes1`…`bytes32`, `uint8`…`uint256`, `int8`…`int256`, and arrays of those) or
  a struct the document defines
- the message has to match the type it claims to be, member for member. A
  declared member that is missing is an error, and so is one no type declares —
  the latter would not be signed, so carrying it means believing something the
  signature will not say
- a value has to fit its declared type: an `address` that is not 20 bytes, a
  `bytes32` that is not 32, a `uint8` of 256 are all refused

`EIP712Domain` is **derived** from the domain and must not be declared in
`types`: only the domain fields actually present take part in the domain
separator, and the entry is generated in EIP-712's own field order, so the type
and the value cannot disagree.

## Nothing is hashed locally

The wallet computes the digest. `TypedData` validates a document and serializes
it — v4 takes the document as a string rather than as a nested object — and that
is all. Computing the domain separator and `hashStruct` locally is
[#45](https://github.com/poteto0/endor.mbt/issues/45); the thing that will need
it is EIP-1271, not this.

The SDK also does not recover the signer from a signature. Verification belongs
to whatever is being convinced — usually your backend, or a contract.
