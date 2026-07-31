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

Reads cost nothing and prompt nobody: `eth_call` and the `eth_get*` family are
evaluated against the node's state and need no signature. Writes are the ones
that spend money, and they are exactly the ones that open a popup.

::: warning About the live demos
The demos drive your **real** wallet on whatever chain it is currently on. The
reading ones cannot cost you anything. [Send ETH](./send-eth/) can: it sends the
amount you type, and it is the only demo on this site that broadcasts a
transaction. Point your wallet at a testnet before using it.
:::

## Start here

[Connect a wallet](./connect/) — everything else assumes a wallet the page can
talk to.
