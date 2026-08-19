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
`Rpc(e)` is the wallet or the node — a rejected prompt, a dropped connection —
and `Abi(e)` means the contract is not the one the caller described, most often
an address that is not the contract it was taken for. No retry helps with the
second. `Deployment(what)` belongs to `deploy` alone. A call the contract itself
refused is `Revert(why)`, `Panic(code)` or `CustomError(…)`, read out of the
revert the node handed back — see [Errors](/guide/errors/) for what each says and
how a custom error gets its arguments back.

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
`balance_of`, `allowance`, `transfer`, `approve`, and — for the transfers in a
receipt's logs — `Erc20::transfer_topic()` to find them and
`Erc20::decode_transfer(log)`, which answers with `(from, to, value)`.
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

Amounts are `BigInt` in the token's smallest unit: `decimals` says where the
point goes, and it is read from the token rather than assumed, so nothing here
scales an amount on its own. Moving the point is
[`Wei::from_units` / `Wei::to_units`](/cookbook/send-eth/#amounts-are-wei), which
takes the scale as an argument for that reason. Reading is four `eth_call`s that cost the user
nothing; `transfer` and `approve` sign, so they prompt and answer with a `TxHash`
whose success is in the receipt.

## The stablecoin preset

`@stablecoin.Stablecoin` — the package is `poteto0/endor/contract/stablecoin` —
is that preset plus the two extensions that make a token a stablecoin: EIP-3009,
which lets a holder sign a transfer for somebody else to submit, and EIP-2612,
which does the same for an approval. A stablecoin *is* an ERC-20, so the whole
of the table above is on it as well — `name`, `symbol`, `decimals`,
`total_supply`, `balance_of`, `allowance`, `transfer`, `approve`, `nonces` and
`domain_separator` all delegate to `@erc20.Erc20`. `token()` hands out the same
token as an `@erc20.Erc20` for passing to something that takes one, and the
`Transfer` log helpers stay there, since they take no token — EIP-3009's own two
logs are read here instead. Both presets also have `contract()`, the
`@contract.Contract` underneath — already carrying `standard_errors()` — for a
function neither of them spells.

| Call                                       | Sends                                                  |
| ------------------------------------------ | ------------------------------------------------------ |
| `transfer_with_authorization(p, submitter~, authorization~, signature~)` | `transferWithAuthorization(...)`  |
| `receive_with_authorization(…)`            | `receiveWithAuthorization(...)` — submitter must be `to` |
| `cancel_authorization(p, submitter~, cancellation~, signature~)` | `cancelAuthorization(...)`        |
| `permit(p, submitter~, permit~, signature~)` | `permit(...)`                                        |
| `…_1271(…)` — the same four                | the `bytes signature` overload FiatTokenV2_2 added     |
| `authorization_state(p, authorizer~, nonce~)` | reads whether the nonce is spent                    |
| `domain(p, chain_id?)`                     | reads `name()` / `version()`, checked against `DOMAIN_SEPARATOR()` |
| `authorization_used_topic()` / `decode_authorization_used(log)` | `AuthorizationUsed` → `(authorizer, nonce)` |
| `authorization_canceled_topic()` / `decode_authorization_canceled(log)` | `AuthorizationCanceled`, the same pair |

`submitter` is who sends the transaction and pays for it, which for EIP-3009 is
never the account whose units move. The `_1271` methods send the second
selector FiatTokenV2_2 gave each of those four, which takes the signature as
`bytes` so a contract wallet's can go through — the caller's to choose, since a
token older than V2_2 does not carry them. The last two rows are the read side:
which nonce a receipt burned, which a `Transfer` log does not say. The documents
themselves are `endor/eips/eip3009` and `endor/eips/eip2612`, which reach no
node: [Move a stablecoin](../../cookbook/stablecoin/) is both halves.

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
| `@abi.decode_log(name~, params~, …)`      | one log, as the event's arguments          |

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

**Not covered:** `bytesN` beyond 32.

## Reading a log

An event's arguments are in two places. The ones Solidity declared `indexed` are
the log's `topics` after the first — `topics[0]` is the signature hash
`@abi.event_topic` computes — and the rest are ABI-encoded in `data`.
`@abi.decode_log` checks `topics[0]`, reads both halves, and answers with one
array in the order the event declares them:

```moonbit
fn transfer_of(log : @endor.Log) -> Array[@abi.AbiValue] raise @abi.AbiError {
  @abi.decode_log(
    name="Transfer",
    params=[
      // event Transfer(address indexed from, address indexed to, uint256 value)
      { ty: Address, indexed: true },
      { ty: Address, indexed: true },
      { ty: Uint(256), indexed: false },
    ],
    topics=log.topics,
    data=log.data,
  )
}
```

`@abi.EventParam` is that pairing — an `AbiType` and whether it is `indexed` —
and it is what the log cannot supply: nothing on the wire says which half a value
came from. A log of another event raises `InvalidData` rather than decoding into
plausible nonsense, which matters because a receipt holds the logs of every
contract the transaction touched.

**An indexed `string`, `bytes`, array or struct comes back as its hash.** A topic
is one 32-byte word and those do not fit in one, so what Solidity puts there is
the `keccak256` of the encoded value. The value was never in the log and cannot
be recovered from it — by anyone, not just by this SDK — so `decode_log` answers
with `Bytes` holding those 32 bytes. A caller with a candidate value hashes it
and compares, which is all a log filter ever does with one.

**Anonymous events are not decoded.** An `anonymous` event writes no signature
hash, so its log has no `topics[0]` to match and its first topic is already an
argument. Nothing in such a log says which event it is, so passing the wrong
parameter list would decode silently into the wrong values instead of raising.
`decode_log` always expects `topics[0]`, and a log of an anonymous event fails
that check; read one with `@abi.decode` over `data` and the topics by hand, where
the assumption is written down as yours.

## Generating a preset — experimental

`@codegen.generate(name, document)` (`abi/codegen`) reads a JSON ABI document and
renders the _source_ of a preset shaped like `@erc20.Erc20` — a struct wrapping a
`Contract`, a method per function, and a topic getter plus a log decoder per
event. `endor-cli abi`, its
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
`address`, `bool`, `string`, `uintN`, `intN` — and _skips_ every other member
rather than approximating it, naming each one in `Generated::skipped` and in a
comment in the generated file. An event's _topic_ is exempt, since it needs only
the signature — its `decode_…` runs into the same limit every other method does,
and an event that loses it keeps the topic, which is what a caller filters logs
with before decoding them by hand. An `anonymous` event generates nothing at all:
its logs carry no `topics[0]` to match or decode. `fallback`, `receive` and
`error` entries are dropped, since nothing generated dispatches to them. Read
what it produces before shipping it.

The document may be the JSON array of ABI members or a **compiler artifact**
holding one — `solc --combined-json abi,bin`, solc's standard JSON, a Foundry
(`bytecode.object`) or a Hardhat (`bytecode`) artifact. An artifact also carries
the creation code, and then the generated struct can put a contract on chain
rather than only call one already there:

| Generated                | From         | Underneath           |
| ------------------------ | ------------ | -------------------- |
| `T::new(address)`        | any document | `Contract::new`      |
| `T::creation_code()`     | an artifact  | the embedded literal |
| `T::deploy(p, from~, …)` | an artifact  | `@contract.deploy`   |

`deploy` takes the constructor's arguments — `value?` as well, if it is `payable`
— and answers with the `T` now on chain. It passes none of `@contract.deploy`'s
waiting knobs: a caller who needs the wait described their own way hands
`creation_code()` to `@contract.deploy` directly, which is why that one is
public.

The creation code is validated as hex when the file is generated, so the
`Hex::from_string` in it cannot fail. Bytecode that _cannot_ be deployed is
skipped with its reason rather than embedded — unlinked library references
(`__$…$__`), the empty bytecode an interface or an abstract contract compiles to,
or a constructor taking a type the generator does not translate. An artifact
holding several contracts is refused by name: one document generates one struct,
and choosing which contract wears the caller's name is not the generator's choice
to make.
