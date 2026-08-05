---
title: ABI and contracts
description: encode / decode on their own, Contract over them, Erc20 over that, and deploy.
---

# ABI and contracts

## Contract

| Function                                  | Underneath                                 | Returns                |
| ----------------------------------------- | ------------------------------------------ | ---------------------- |
| `Contract::call(p, name~, …)`             | `eth_call`                                 | `Array[@abi.AbiValue]` |
| `Contract::send(p, from~, name~, …)`      | `eth_sendTransaction`                      | `@endor.TxHash`        |
| `deploy(p, from~, bytecode~, …)`          | `eth_sendTransaction` + `wait_for_receipt` | `@contract.Contract`   |
| `send_deployment(p, from~, bytecode~, …)` | `eth_sendTransaction`                      | `@endor.TxHash`        |

`@contract.Contract` is the ABI layer over `eth_call` / `eth_sendTransaction`:
`call` encodes the arguments, evaluates the call and decodes the answer as
`outputs`; `send` encodes the arguments and broadcasts them, so it prompts and
answers with a hash. Neither registers an ABI up front — each call names the
function it makes:

```moonbit
async fn owner_of(
  wallet : @browser.BrowserProvider,
  nft : @endor.Address,
  id : BigInt,
) -> Array[@abi.AbiValue] raise @contract.ContractError {
  @contract.Contract::new(nft).call(
    wallet,
    name="ownerOf",
    inputs=[Uint(256)], // the parameter types, which fix the selector
    args=[Uint(id)], // the values, checked against those types
    outputs=[Address], // how to read the answer back
    // from? and block? are optional, as for a raw eth_call
  )
}
```

`inputs`, `args` and `outputs` all default to empty, so a no-argument getter that
answers nothing is `call(p, name="poke")`.

Errors arrive as `@contract.ContractError`, which keeps the failures apart:
`Rpc(e)` is the wallet or the node — a rejected prompt, a revert — and `Abi(e)`
means the contract is not the one the caller described, most often an address
that is not the contract it was taken for. No retry helps with the second.
`Deployment(what)` is the third and belongs to `deploy` alone.

## Deploying

A transaction with no recipient deploys its `data`, so a deployment is the same
`eth_sendTransaction` with `to` left out and the creation code in its place:

```moonbit
async fn deploy_one(
  wallet : @browser.BrowserProvider,
  me : @endor.Address,
  code : @endor.Hex,
) -> @endor.Address raise @contract.ContractError {
  let deployed = @contract.deploy(
    wallet,
    from=me,
    bytecode=code, // the creation code, as @endor.Hex
    inputs=[Uint(256)], // the constructor's parameter types
    args=[Uint(1000N)], // encoded behind the code — no selector
    // value?, confirmations?, timeout?, poll_interval? are optional
  )
  deployed.address()
}
```

Constructor arguments carry no selector because a constructor has no name to
hash: `@contract.deployment_data`, which builds the `data` and is public for a
caller that sends it some other way, is `@abi.encode_call` without those four
bytes — so a constructor taking nothing leaves the creation code exactly as it
was.

`deploy` waits, since the address only exists once the transaction is mined — it
is in the receipt's `contract_address`. `send_deployment` is the same broadcast
without the wait, for a caller that wants the hash while the transaction is still
pending. A deployment that reverted has a receipt too, and one with no address in
it, so both are raised as `Deployment(what)` rather than handed back as an
absence to notice.

## The ERC-20 preset

`@erc20.Erc20` — the package is `poteto0/endor/contract/erc20` — spells the
standard interface once: `name`, `symbol`, `decimals`, `total_supply`,
`balance_of`, `allowance`, `transfer`, `approve`, and `Erc20::transfer_topic()`
for finding transfers in a receipt's logs. Two more are EIP-2612's rather than
ERC-20's — `nonces` and `domain_separator`, which a token without permit support
does not have — and what they are for is
[Approve without a transaction](../../cookbook/permit/).

```moonbit
async fn token_calls(
  wallet : @browser.BrowserProvider,
  address : @endor.Address,
  who : @endor.Address,
  to : @endor.Address,
) -> Unit raise @contract.ContractError {
  let token = @erc20.Erc20::new(address)
  let amount = token.balance_of(wallet, who) // BigInt, in the token's own unit
  let hash = token.transfer(wallet, from=who, to~, amount~) // prompts
  println("sent \{amount}, broadcast as \{hash}")
}
```

Amounts are `BigInt` in the token's smallest unit, never scaled: `decimals` says
where the point goes, and moving it is a presentation concern the SDK stays out
of, exactly as it does for `Wei`. Reading is four `eth_call`s that cost the user
nothing; `transfer` and `approve` sign, so they prompt and answer with a `TxHash`
whose success is in the receipt.

## Encoding on its own

`@abi` is the encoding underneath, usable without a provider:

| Function                                  | Answers                                    |
| ----------------------------------------- | ------------------------------------------ |
| `@abi.encode(types, values)`              | the values, ABI-encoded, as `@endor.Hex`   |
| `@abi.decode(types, data)`                | `Array[@abi.AbiValue]`                     |
| `@abi.encode_call(name~, inputs~, args~)` | selector plus arguments — calldata         |
| `@abi.signature(name~, inputs~)`          | `"transfer(address,uint256)"`              |
| `@abi.selector(signature)`                | the 4 bytes calldata starts with           |
| `@abi.event_topic(signature)`             | the 32-byte topic an event is logged under |

`@abi.AbiType` describes a parameter — `Uint(256)`, `Address`, `FixedBytes(32)`,
`Array(String)`, `FixedArray(t, k)`, `Tuple([…])` — and `@abi.AbiValue` carries
the value. The types travel alongside the values because ABI data carries no type
tags: only the type says how wide a `uint` is (and so whether the value fits),
and only the type tells a fixed-length array from a dynamic one.

`@abi.AbiError` is `InvalidAbiType` (a type no contract can declare, `uint7`),
`InvalidValue` (a value that does not fit its type) or `InvalidData` (encoded
bytes that will not read back as the expected types). It is defined in `types`
alongside `AbiType`, because `AbiType::name` checks the same width and size rules
`@abi.encode` does, so both raise it; `abi` re-exports the type. The rules
themselves are predicates in `@codec`, which is also where the hex-digit and word
arithmetic both this layer and `@eip712` work in lives.

**Not covered:** `bytesN` beyond 32, and decoding a log's indexed arguments.

## Generating a preset — experimental

`@codegen.generate(name, document)` (`abi/codegen`) reads a JSON ABI document and
renders the *source* of a preset shaped like `@erc20.Erc20` — a struct wrapping a
`Contract`, a method per function, a topic getter per event. `endor-cli abi`, its
command-line front end, lives in `cmd/`, which is a **separate module**
(`poteto0/endor-cli`) and is not part of what this one publishes — it is
installed as a binary, not depended on.

```sh
moon install poteto0/endor-cli/endor-cli
endor-cli init      # writes endor.yaml
endor-cli abi       # reads ./abi, writes ./outputs
```

**This is experimental and is not part of the stable surface.** It generates only
what it can type without guessing — parameters and single return values of
`address`, `bool`, `string`, `uintN`, `intN` — and *skips* every other member
rather than approximating it, naming each one in `Generated::skipped` and in a
comment in the generated file. Events are exempt, since a topic needs only the
signature; `fallback`, `receive` and `error` entries are dropped, since nothing
generated dispatches to them. Read what it produces before shipping it.

The document may be the JSON array of ABI members or a **compiler artifact**
holding one — `solc --combined-json abi,bin`, solc's standard JSON, a Foundry
(`bytecode.object`) or a Hardhat (`bytecode`) artifact. An artifact also carries
the creation code, and then the generated struct can put a contract on chain
rather than only call one already there:

| Generated                | From        | Underneath           |
| ------------------------ | ----------- | -------------------- |
| `T::new(address)`        | any document | `Contract::new`     |
| `T::creation_code()`     | an artifact  | the embedded literal |
| `T::deploy(p, from~, …)` | an artifact  | `@contract.deploy`   |

`deploy` takes the constructor's arguments — `value?` as well, if it is `payable`
— and answers with the `T` now on chain. It passes none of `@contract.deploy`'s
waiting knobs: a caller who needs the wait described their own way hands
`creation_code()` to `@contract.deploy` directly, which is why that one is
public.

The creation code is validated as hex when the file is generated, so the
`Hex::from_string` in it cannot fail. Bytecode that *cannot* be deployed is
skipped with its reason rather than embedded — unlinked library references
(`__$…$__`), the empty bytecode an interface or an abstract contract compiles to,
or a constructor taking a type the generator does not translate. An artifact
holding several contracts is refused by name: one document generates one struct,
and choosing which contract wears the caller's name is not the generator's choice
to make.
