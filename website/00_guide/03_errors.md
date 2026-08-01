---
title: Errors
description: Four suberrors, and which of them a dapp actually has to branch on.
islands:
  - address_tool
---

# Errors

Nothing in the SDK panics on a wallet-side failure. Everything that can go wrong
arrives as one of four suberrors, and which one you catch says where the problem
was.

| Suberror                    | Raised by                        | Means                                       |
| --------------------------- | -------------------------------- | ------------------------------------------- |
| `@provider.ProviderError`   | every RPC call                   | the wallet, the node, or the connection     |
| `@contract.ContractError`   | `Contract`, `Erc20`, `deploy`    | one of the above, or the ABI                |
| `@endor.AbiError`           | `@abi.encode` / `decode`         | a type or a value the ABI cannot carry      |
| `@endor.CodecError`         | a domain type's constructor      | a string that is not the thing it claims    |

## ProviderError

```moonbit
async fn every_branch(wallet : @browser.BrowserProvider) -> Unit {
  try {
    let _ = @provider.request_accounts(wallet)

  } catch {
    // 4001 — the user saw the prompt and said no. Not an error to report as a
    // failure; it is an answer.
    UserRejected => println("declined")
    // 4100 — this page was never authorized for that account
    Unauthorized => println("not authorized")
    // 4200 — the wallet does not implement the method at all
    UnsupportedMethod => println("this wallet cannot do that")
    // 4900 / 4901 — the provider lost its connection, or lost the chain
    Disconnected => println("the provider is disconnected")
    ChainDisconnected => println("the provider lost that chain")
    // 4902 — the wallet does not know the chain. `switch_or_add_chain` already
    // handles this one for you.
    UnrecognizedChain => println("unknown chain")
    // no wallet extension at all: raised by BrowserProvider::require
    NotInstalled => println("install a wallet")
    // wait_for_receipt ran out of time. Deliberately not the same answer as
    // `transaction_receipt` returning None.
    Timeout(why) => println("gave up: \{why}")
    // anything else the wallet said, with the code it said it under
    Rpc(code~, message~) => println("wallet error \{code}: \{message}")
  }
}
```

In practice a dapp branches on two of them — `UserRejected`, because declining is
a normal thing for a person to do, and `NotInstalled`, because it needs a
different screen — and reports the rest:

```moonbit
async fn the_usual_shape(wallet : @browser.BrowserProvider) -> Unit {
  try {
    let addr = @provider.require_account(wallet)
    println("connected as \{addr}")
  } catch {
    NotInstalled => println("install a wallet extension to continue")
    UserRejected => println("connection declined")
    e => println("something went wrong: \{e}")
  }
}
```

`ProviderError::from_code` is what maps an EIP-1193 / EIP-1474 code onto those
variants, and `ProviderError::internal` is what the SDK's own failures use — a
malformed answer, a value the wallet returned that is not the type it must be.

## ContractError

The contract layer keeps the wallet's failures apart from the ABI's, because
they call for completely different responses:

```moonbit
async fn token_errors(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
  who : @endor.Address,
) -> Unit {
  try {
    let amount = @erc20.Erc20::new(token).balance_of(wallet, who)
    println("holds \{amount}")
  } catch {
    // the wallet or the node: a rejected prompt, a revert, a dropped connection
    Rpc(e) => println("the wallet said: \{e}")
    // it answered, but not as the contract you described — most often an
    // address that holds no contract, or holds one that is not an ERC-20.
    // Retrying does not help with this one.
    Abi(e) => println("that is not an ERC-20: \{e}")
    // `deploy` alone: the transaction reverted, or left no contract behind
    Deployment(what) => println("deployment failed: \{what}")
  }
}
```

## AbiError and CodecError

`AbiError` is `InvalidAbiType` (a type no contract can declare, `uint7`),
`InvalidValue` (a value that does not fit its declared type) and `InvalidData`
(bytes that will not read back as the expected types).

`CodecError` is what a domain type's constructor raises, and it is where user
input gets rejected. **Try it:** type into the box and the first line names the
variant that came back — delete a character for `InvalidLength`, put a `z` in it
for `InvalidHex`, change the case of one letter for `InvalidChecksum`.

<Island name="address_tool" trigger="visible" />


```moonbit
fn parse_user_input(typed : String) -> Unit {
  let addr = @endor.Address::from_string(typed) catch {
    // not hex at all, or hex with a `0x` prefix missing
    InvalidHex(what) => {
      println("not hex: \{what}")
      return
    }
    // hex, but not twenty bytes of it
    InvalidLength(what) => {
      println("wrong length: \{what}")
      return
    }
    // mixed case, and the case does not match the EIP-55 checksum — one
    // mistyped character in an address somebody copied
    InvalidChecksum(what) => {
      println("checksum failed: \{what}")
      return
    }
    e => {
      println("error: \{e}")
      return
    }
  }
  println("ok: \{addr.to_checksum_string()}")
}
```

The checksum branch is the one worth wiring to real UI. It is the difference
between telling somebody they mistyped and sending their money to an address
nobody holds the key to.

## Events raise nothing

An event arrives outside any call you made, so there is nowhere to raise to. A
payload that fails to decode — a `chainChanged` that is not a hex quantity, a
`disconnect` with no numeric `code` — is **dropped**: the handler is not called,
nothing is raised, the subscription stays live, and the next well-formed event is
delivered normally.

The one event that carries an error carries it as a value:

```moonbit
fn disconnect_handler(
  wallet : @browser.BrowserProvider,
) -> @provider.Subscription {
  // the ProviderError is the payload, not a raise
  @provider.on_disconnect(wallet, error => println("gone: \{error}"))
}
```
