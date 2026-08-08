---
title: Escape hatch
description: Provider::request reaches any method, and the same codecs read its answer back.
---

# Escape hatch

`Provider::request` takes any method name. It returns raw `Json` and gives up the
typed surface, so prefer the helpers wherever they exist — but nothing in the SDK
is a ceiling.

```moonbit
async fn transaction_at(
  wallet : @browser.BrowserProvider,
  block : @endor.BlockTag,
  index : @endor.Quantity,
) -> Json raise @provider.ProviderError {
  // a transaction is wrapped when it is asked for by hash
  // (`transaction_by_hash`); by position in a block it is not
  wallet.request(
    method_name="eth_getTransactionByBlockNumberAndIndex",
    params=Json::array([block.to_json(), index.to_json()]),
  )
}
```

Errors still arrive as `ProviderError`: the FFI boundary maps the wallet's error
code through `ProviderError::from_code`, and an answer that is not a well-formed
envelope becomes `MalformedResponse`. What `request` does *not* do is decode —
so a `result` you then read yourself raises a `CodecError`, not the `Decode` the
typed helpers wrap it in.

## Decoding what comes back

The raw `Json` can be read with the same codecs the helpers use:

```moonbit
fn decode_by_hand(answer : Json) -> Unit raise @endor.CodecError {
  match answer {
    { "blockNumber": block, "from": from, "value": value, .. } => {
      // any `0x` quantity: block numbers, nonces, gas
      let block = @endor.Quantity::from_json(block)
      // an address, checksum and length checked
      let from = @endor.Address::from_json(from)
      // a wei-denominated one
      let value = @endor.Wei::from_json(value)
      println("\{from} sent \{value.to_bigint()} wei in block \{block.to_uint64()}")
    }
    _ => println("not the shape expected")
  }
}
```

| Codec                       | For                                          |
| --------------------------- | -------------------------------------------- |
| `@endor.Quantity::from_json` | any `0x` quantity — block numbers, nonces, gas |
| `@endor.Wei::from_json`     | wei-denominated quantities                    |
| `@endor.Address::from_json` | an address, length and checksum checked       |
| `@endor.Hex::from_json`     | anything else that is `0x`-prefixed bytes     |
| `@endor.TxHash::from_json`  | a hash, narrowed to exactly 32 bytes          |

Each raises `@endor.CodecError` rather than answering something wrong, so a
malformed answer is caught where it arrives instead of three layers later.

## Writing against the trait

`Provider` is a trait, so code that only needs "something that answers RPC" can
take one and be tested against `@provider.MockProvider`:

```moonbit
async fn[P : @provider.Provider] head_of(provider : P) -> UInt64 raise {
  // works against a browser wallet, a mock, and anything else implementing
  // the trait
  @provider.block_number(provider)
}
```

That is how the SDK's own test suite runs with no browser in it.
