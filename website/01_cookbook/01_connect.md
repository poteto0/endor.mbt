---
title: Connect a wallet
description: Find the injected provider, ask for an account, read the chain.
islands:
  - address_tool
  - connect
---

# Connect a wallet

Everything else in this cookbook starts here: a wallet the page can talk to, and
an account it is allowed to ask about.

<Island name="connect" trigger="load" />

The widget above is this page's code, compiled. It is
[`website/islands/connect`](https://github.com/poteto0/endor.mbt/tree/main/website/islands/connect)
— the same `poteto0/endor` a `moon add` gives you, driving whatever wallet your
browser has.

## The three calls

```moonbit
async fn connect() -> Unit {
  try {
    // raises NotInstalled when no wallet extension is present
    let wallet = @browser.BrowserProvider::require()
    // eth_requestAccounts — prompts if this page is not connected yet
    let addr = @provider.require_account(wallet)
    let chain = @provider.chain_id(wallet) // eth_chainId
    println("\{addr.to_checksum_string()} on chain \{chain.to_uint64()}")
  } catch {
    NotInstalled => println("no wallet detected")
    UserRejected => println("the user declined")
    e => println("error: \{e}")
  }
}
```

`BrowserProvider::require` is the only part that touches the browser: it reads
`globalThis.ethereum` and raises `NotInstalled` when nothing is there.
`BrowserProvider::get` is the same lookup answering `None`, for a page that
wants to render a "install a wallet" state rather than handle an error.

## Prompting, and not prompting

There are two ways to ask who is connected, and the difference is a popup:

| Call                              | JSON-RPC              | Prompts? |
| --------------------------------- | --------------------- | -------- |
| `@provider.request_accounts(p)`   | `eth_requestAccounts` | yes, when not connected |
| `@provider.accounts(p)`           | `eth_accounts`        | never    |

`accounts` answers an empty array when the page was never authorized, which is
what makes it the right call on page load: it tells you whether you are
connected without asking anyone anything. `request_accounts` belongs behind a
button, because every wallet gates its prompt behind a user gesture.

`require_account` is `request_accounts` with the empty case already turned into
an error, since a dapp that asked for an account and got none has nothing to do
with the answer:

```moonbit
async fn who(wallet : @browser.BrowserProvider) -> @endor.Address raise {
  @provider.require_account(wallet) // raises Unauthorized rather than answering None
}
```

## The address is a type

What comes back is an `@endor.Address`, not a string:

```moonbit
fn address_forms(addr : @endor.Address) -> Unit {
  println(addr.to_string()) // lowercase, the form that goes on the wire
  println(addr.to_checksum_string()) // EIP-55, the form to show a human
}
```

Building one from user input is where a typo is caught. **Try it:** the box
below runs `Address::from_string` on whatever you type, every keystroke, and
shows what it answered. Change one character of the checksummed address and the
first line turns into the error it raised — the wire form and the EIP-55 form
under it are what you get when it does not.

<Island name="address_tool" trigger="visible" />

No wallet is involved, and nothing is sent anywhere: this is the constructor and
`crypto/keccak256`, running in the page.


```moonbit
fn parse_address(typed : String) -> Unit {
  let addr = @endor.Address::from_string(typed) catch {
    // wrong length, a non-hex digit, or a broken EIP-55 checksum
    e => {
      println("not an address: \{e}")
      return
    }
  }
  println("ok: \{addr.to_checksum_string()}")
}
```

A mixed-case address is checked against its EIP-55 checksum, so a single mistyped
character is rejected here rather than sending someone's money to an address
nobody holds the key to.

## What the demo does past the three calls

The SDK caches nothing — no current account, no current chain — so the widget
holds both itself and subscribes to the events that say they went stale. That is
[React to wallet changes](/cookbook/events/), and it is why the fields update
when you switch account in the extension without touching the page.

<div class="alert alert--status" role="note">
  <div class="alert__title">Next</div>
  <div class="alert__description">

[Send ETH](/cookbook/send-eth/) — the first call that spends money, and so the
first that always prompts.

  </div>
</div>
