---
title: Call any contract
description: Contract::call and send, with the types spelled out — and deploy, for one that is not on chain yet.
---

# Call any contract

`Erc20` is a preset. Underneath it is `Contract`, which is `eth_call` /
`eth_sendTransaction` with the arguments encoded and the answer decoded. Nothing
is registered up front — each call names the function it makes.

## Reading

```moonbit
async fn owner_of(
  wallet : @browser.BrowserProvider,
  nft : @endor.Address,
  id : BigInt,
) -> @endor.Address? raise @contract.ContractError {
  let values = @contract.Contract::new(nft).call(
    wallet,
    name="ownerOf",
    inputs=[Uint(256)], // the parameter types, which fix the selector
    args=[Uint(id)], // the values, checked against those types
    outputs=[Address], // how to read the answer back
  )
  guard values is [Address(owner)] else { return None }
  Some(owner)
}
```

`inputs`, `args` and `outputs` all default to empty, so a no-argument getter that
answers nothing is `call(p, name="poke")`. `from` and `block` are optional too,
the same as on a raw `eth_call`.

The types travel alongside the values because ABI data carries no type tags: only
the type says how wide a `uint` is — and so whether the value fits — and only the
type tells a fixed-length array from a dynamic one.

## Writing

```moonbit
async fn set_number(
  wallet : @browser.BrowserProvider,
  target : @endor.Address,
  from : @endor.Address,
  n : BigInt,
) -> @endor.TxHash raise @contract.ContractError {
  // prompts, broadcasts, and answers with the hash. What it did is in the
  // receipt.
  @contract.Contract::new(target).send(
    wallet,
    from~,
    name="setNumber",
    inputs=[Uint(256)],
    args=[Uint(n)],
  )
}
```

## Deploying

A transaction with no recipient deploys its `data`, so a deployment is the same
`eth_sendTransaction` with `to` left out and the creation code in its place:

```moonbit
async fn put_on_chain(
  wallet : @browser.BrowserProvider,
  me : @endor.Address,
  code : @endor.Hex, // the creation code, from your compiler's artifact
) -> @endor.Address raise @contract.ContractError {
  let deployed = @contract.deploy(
    wallet,
    from=me,
    bytecode=code,
    inputs=[Uint(256)], // the constructor's parameters, encoded behind the code
    args=[Uint(1000N)],
  )
  deployed.address()
}
```

Constructor arguments carry no selector, because a constructor has no name to
hash. `deploy` waits for the receipt, since the address only exists once the
transaction is mined — it is the receipt's `contract_address`.
`@contract.send_deployment` is the same broadcast without the wait, for a UI that
wants the `TxHash` while the deployment is still pending.

A deployment that reverted has a receipt too, and one with no address in it. Both
come back as `Deployment(what)` rather than as an absence to notice.

## The encoding on its own

`endor/abi` is usable with no provider in hand, for when the call goes out some
other way:

```moonbit
fn calldata(to : @endor.Address) -> Unit raise {
  // the four bytes a call starts with
  println(@abi.selector("transfer(address,uint256)").to_string())
  // the topic an event is logged under
  println(@abi.event_topic("Transfer(address,address,uint256)").to_string())
  // a whole call: selector plus encoded arguments
  let data = @abi.encode_call(
    name="transfer",
    inputs=[Address, Uint(256)],
    args=[Address(to), Uint(1000N)],
  )
  println(data.to_string())
  // and back again — the arguments on their own, with the selector dropped
  let arguments = @abi.encode([Address, Uint(256)], [Address(to), Uint(1000N)])
  let values = @abi.decode([Address, Uint(256)], arguments)
  println("\{values.length()} value(s)")
}
```

`@abi.AbiType` describes a parameter — `Uint(256)`, `Address`, `FixedBytes(32)`,
`Array(String)`, `FixedArray(t, k)`, `Tuple([…])` — and `@abi.AbiValue` carries
the value.

Not covered: `bytesN` beyond 32, and decoding a log's *indexed* arguments.

## Generating a preset

`endor-cli abi` renders the source of a preset shaped like `Erc20` from a JSON
ABI document, or from a compiler artifact — which carries the creation code as
well, and so also generates a `deploy`.

```sh
moon install poteto0/endor-cli/endor-cli
endor-cli init      # writes endor.yaml
endor-cli abi       # reads ./abi, writes ./outputs
```

**Experimental**, and not required to use the SDK. It generates only what it can
type without guessing and skips the rest by name rather than approximating it, so
read what it produces before shipping it.
[`cmd/README.md`](https://github.com/poteto0/endor.mbt/blob/main/cmd/README.md)
has the details.
