---
title: Cookbook
description: One page per task, each with a demo you can drive against a real wallet.
---

# Cookbook

Each page here is one thing a dapp does, with the code that does it and a widget
that runs that code in your browser, against whatever wallet you have installed.

The demos are not mockups. Each is a package of
[`website/islands/`](https://github.com/poteto0/endor.mbt/tree/main/website/islands)
— MoonBit compiled to an ES module, calling `poteto0/endor` as it stands in the
repository. If a recipe here stops working, the demo on the page stops working
too.

Two kinds sit on these pages. The ones with a button drive your wallet. The ones
that answer **as you type** need no wallet at all, because the function they are
calling needs none: `Address::from_string` deciding whether what you typed is an
address and which rule it broke, the scaling between ether and wei, `keccak256`
turning a signature into a selector. Those are placed beside the paragraph that
explains them, so the behaviour and the description are the same thing.

## Recipes

| Page                                         | Prompts the wallet? | Costs gas? |
| -------------------------------------------- | ------------------- | ---------- |
| [Connect a wallet](./connect/)               | yes, once           | no         |
| [Send ETH](./send-eth/)                      | yes                 | **yes**    |
| [Read an ERC-20](./erc20/)                   | no                  | no         |
| [Switch chains](./switch-chain/)             | yes                 | no         |
| [Wait for a receipt](./receipts/)            | —                   | no         |
| [Sign a message](./sign/)                    | yes                 | no         |
| [Call any contract](./contract/)             | reads no, writes yes | writes only |
| [React to wallet changes](./events/)         | no                  | no         |
| [Transfer without gas](./gasless-transfer/)  | yes                 | no, not for you |
| [Approve without a transaction](./permit/)   | yes                 | no, not for you |
| [Read without a wallet](./http-rpc/)         | no — there is none  | no         |

And the ones that need no wallet at all:

| Widget                                                    | Answers                                        |
| --------------------------------------------------------- | ---------------------------------------------- |
| [`Address::from_string`](./connect/#the-address-is-a-type) | accepted, or which `CodecError` it raises       |
| [ether ⇄ wei](./send-eth/#amounts-are-wei)                 | `Wei::from_units` at any scale, and back        |
| [`selector` / `event_topic`](./contract/#the-encoding-on-its-own) | keccak256 of a signature                 |

Reads cost nothing and prompt nobody: `eth_call` and the `eth_get*` family are
evaluated against the node's state and need no signature. Writes are the ones
that spend money, and they are exactly the ones that open a popup.

That is also why the last recipe needs no wallet at all: [Read without a
wallet](./http-rpc/) points the same typed helpers at a node URL over HTTP,
which works in a script, a CLI or on a server as well as in a page. It is the
one page here with no demo on it, and it says why.

<div class="alert alert--warning" role="note">
  <div class="alert__title">About the live demos</div>
  <div class="alert__description">

The demos drive your **real** wallet on whatever chain it is currently on. The
reading ones cannot cost you anything. [Send ETH](./send-eth/) can: it sends the
amount you type, and it is the only demo on this site that broadcasts a
transaction. Point your wallet at a testnet before using it.

  </div>
</div>

## Start here

[Connect a wallet](./connect/) — everything else assumes a wallet the page can
talk to.
