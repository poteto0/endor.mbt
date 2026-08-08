---
title: Errors
description: Four suberrors, the three questions a dapp asks of any of them, and what is worth retrying.
islands:
  - address_tool
---

# Errors

Nothing in the SDK panics on a wallet-side failure. Everything that can go wrong
arrives as one of four suberrors, and which one you catch says where the problem
was. All four are spelled from `@endor`, so catching them costs no extra import.

| Suberror                | Raised by                     | Means                                    |
| ----------------------- | ----------------------------- | ---------------------------------------- |
| `@endor.ProviderError`  | every RPC call                | the wallet, the node, or the connection  |
| `@endor.ContractError`  | `Contract`, `Erc20`, `deploy` | one of the above, the ABI, or a revert   |
| `@endor.AbiError`       | `@abi.encode` / `decode`      | a type or a value the ABI cannot carry   |
| `@endor.CodecError`     | a domain type's constructor   | a string that is not the thing it claims |

## The three questions

Matching every variant is rarely what a dapp wants. Almost every failure is
handled by asking three things, and each of them is one call — on
`ProviderError` and on `ContractError` alike, so the same handler works whether
you caught the wallet's failure or the contract's.

```moonbit
async fn one_handler(wallet : @browser.BrowserProvider) -> Unit {
  try {
    let _ = @provider.request_accounts(wallet)
  } catch {
    // 1. was this the user saying no? Then say nothing: declining is an answer,
    //    not a failure, and a dialog about it is noise.
    UserRejected => ()
    e =>
      // 2. is trying again worth anything? True for a connection that did not
      //    happen, a node asking for a moment, a request that timed out; false
      //    for anything already decided.
      if e.is_retryable() {
        println("\{e.message()} Trying again…")
      } else {
        // 3. what do I put on the screen? `message()` is one line written for a
        //    person. `Show` — `"\{e}"` — is the developer's view, for the log.
        println(e.message())
      }
  }
}
```

`message()` never contains a variant name, a URL or a JSON-RPC code, so it is
safe to render as-is. `"\{e}"` contains all three, so it belongs in a log and
never in a dialog. Both are on all four suberrors. `ProviderError` and
`ContractError` carry a third, `code()`, giving back the EIP-1193 / EIP-1474
number when there was one and `None` for the failures that never reached the
protocol — `AbiError` and `CodecError` never do, so they do not have it.

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
    // a wait that ran out: `wait_for_receipt` polling, or an HTTP request going
    // unanswered. Deliberately not the same answer as `transaction_receipt`
    // returning None.
    Timeout(why) => println("gave up: \{why}")
    // the contract refused the call, and the node handed back the revert it
    // refused with. What that revert *says* needs the ABI — catch it as a
    // `ContractError` below and it arrives decoded.
    Reverted(data~, ..) => println("the contract reverted: \{data}")
    // nothing got through: no connection, DNS, TLS, a socket that closed
    Transport(why) => println("could not reach it: \{why}")
    // something answered, with a status that is not 2xx. 429 and 5xx are worth
    // retrying; 401 and 403 are an API key that is wrong or missing.
    HttpStatus(code~, url~) => println("HTTP \{code} from \{url}")
    // a 2xx body that is not JSON-RPC at all — a proxy, a captive portal, the
    // wrong URL. Retrying gets the same body back.
    MalformedResponse(why) => println("that was not JSON-RPC: \{why}")
    // the answer was well-formed and still not the type the method promises.
    // The CodecError is kept as it was raised, not flattened into a string.
    Decode(method_name~, cause~) => println("\{method_name} answered: \{cause}")
    // your own mistake, caught before any I/O: a URL that is not a URL
    Config(what) => println("misconfigured: \{what}")
    // anything else the wallet or the node said, with the code it said it under
    Rpc(code~, message~) => println("wallet error \{code}: \{message}")
  }
}
```

The last five are the ones added in 0.6 (#113). Before them every one of these
was the same `Rpc(code=-32603, …)`, which meant "the node had an internal
error" even when no request had left the process — so telling a typo in a URL
apart from a node that was down meant matching on the message string.

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
variants. `ProviderError::internal` is deprecated: what used to be flattened
into it now has a variant of its own, and matching on it means matching on
whichever variant says what actually happened.

### What to retry

`is_retryable()` is the summary, and this is what it reads:

| Retry                 | Do not retry                                        |
| --------------------- | --------------------------------------------------- |
| `Transport`           | `UserRejected`, `Unauthorized`, `UnsupportedMethod` |
| `Timeout`             | `NotInstalled`, `UnrecognizedChain`                 |
| `HttpStatus` 429, 5xx | `HttpStatus` 401, 403 — the API key, not the load   |
| `Rpc(-32005)`         | `MalformedResponse`, `Decode`, `Config`, `Reverted` |

Back off between attempts rather than looping: a `429` is the node asking for a
moment, and a retry that arrives immediately is another `429`.

## ContractError

The contract layer keeps three things apart, because they call for completely
different responses: the wallet's failures, the ABI's, and the contract saying
no on purpose.

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
    // the wallet or the node: a rejected prompt, a dropped connection
    Rpc(e) => println("the wallet said: \{e}")
    // it answered, but not as the contract you described — most often an
    // address that holds no contract, or holds one that is not an ERC-20.
    // Retrying does not help with this one.
    Abi(e) => println("that is not an ERC-20: \{e}")
    // `deploy` alone: the transaction reverted, or left no contract behind
    Deployment(what) => println("deployment failed: \{what}")
    // the contract refused on purpose and said why: `require(cond, "…")`
    Revert(why) => println("the contract said: \{why}")
    // it hit one of the compiler's own checks — an overflow, a division by
    // zero, an index out of bounds. That is a bug in the contract, not in the
    // call.
    Panic(code) => println("the contract broke: \{@contract.panic_reason(code)}")
    // a custom error. The name and the arguments are there when the contract
    // was built with its `error` declarations; otherwise the selector is.
    CustomError(name=Some(name), args~, ..) =>
      println("\{name} said \{args.length()} thing(s)")
    CustomError(selector~, ..) => println("reverted with \{selector}")
  }
}
```

The last three are new in the reverting direction: a call that a contract
refuses arrives as the reason it refused with, not as the node's
`"execution reverted"` string. A custom error decodes down to its arguments when
the contract knows its own `error` declarations, which is what
`Contract::new(address, errors~)` is for — and what `endor-cli abi` generates
for you:

```moonbit
fn declared_errors(at : @endor.Address) -> @contract.Contract {
  @contract.Contract::new(at, errors=[
    { name: "InsufficientBalance", inputs: [Uint(256), Uint(256)] },
  ])
}
```

Without them a custom error still comes back — as `CustomError` holding the
four-byte selector and the raw data, which is all the revert itself carried.

`ContractError` answers the same three questions as `ProviderError`, delegating
the ones that came from the wallet, plus one of its own: `revert_reason()`, the
string a `require(cond, "…")` carried, and `None` for everything that is not a
plain revert. It is usually the only thing worth showing:

```moonbit
async fn transfer_or_say_why(
  wallet : @browser.BrowserProvider,
  token : @endor.Address,
  from~ : @endor.Address,
  to~ : @endor.Address,
  amount~ : @endor.Wei,
) -> Unit {
  try {
    let _ = @erc20.Erc20::new(token).transfer(
      wallet,
      from~,
      to~,
      amount=amount.to_bigint(),
    )
    println("sent")
  } catch {
    // declining is an answer, so it is handled before anything is explained
    Rpc(UserRejected) => ()
    e =>
      match e.revert_reason() {
        // the contract's author wrote this string for exactly this moment
        Some(reason) => println("the token refused: \{reason}")
        None => println(e.message())
      }
  }
}
```

## AbiError and CodecError

`AbiError` is `InvalidAbiType` (a type no contract can declare, `uint7`),
`InvalidValue` (a value that does not fit its declared type) and `InvalidData`
(bytes that will not read back as the expected types).

`CodecError` is what a domain type's constructor raises, and it is where user
input gets rejected. Its variants split on what is wrong with the value: four
about the **form** (`InvalidHex`, `InvalidLength`, `InvalidChecksum`,
`InvalidJson`) and `InvalidValue` about the **meaning** — a well-formed value
that says something the type cannot hold.

**Try it:** type into the box and the first line names the variant that came
back — delete a character for `InvalidLength`, put a `z` in it for
`InvalidHex`, change the case of one letter for `InvalidChecksum`.

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
