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

## Two wallets installed

`globalThis.ethereum` is whichever extension won the race to inject itself: with
two wallets installed, which one `require()` hands back is not yours to decide.
[EIP-6963](https://eips.ethereum.org/EIPS/eip-6963) is the way out — the page
dispatches `eip6963:requestProvider`, and every wallet answers with its own
provider and a description of itself.

```moonbit
async fn choose() -> Unit {
  // waits ~300ms for wallets to answer, then reports what did
  for wallet in @browser.BrowserProvider::discover() {
    match wallet.info {
      // an announced wallet: `rdns` is the identity to key on, `name` and
      // `icon` are what to draw
      Some(info) => println("\{info.name} (\{info.rdns})")
      // the legacy `globalThis.ethereum`, which announced nothing and so names
      // itself nowhere
      None => println("injected wallet")
    }
  }
}
```

An announcement comes from whichever extension is installed, so one whose fields
are not spelled the way EIP-6963 says never reaches the picker — `icon` above
all, which is drawn in an `<img src>` and so must be a `data:image/` URI rather
than a `javascript:` or remote one. What passes is still the wallet's own claim:
`rdns` is what to key on, not a reason to trust one.

Each `wallet.provider` is a `BrowserProvider` like any other, so the account and
chain calls above work unchanged once the user has picked one. Nothing is
remembered: the SDK is stateless, and which wallet the user chose is the page's
to hold.

`discover` answers an empty array only when there is no wallet at all — when
nothing announces but something is injected, the injection is what comes back,
so a page written against EIP-6963 still works with a wallet that only injects.

Enumeration has no real end: a wallet can be woken after the page is up and will
announce itself then. `discover`'s deadline is a convenience for drawing a
picker once; subscribe instead when the list should keep up.

```moonbit
fn watch_wallets() -> @provider.Subscription {
  @browser.BrowserProvider::on_announce((info, _provider) => println(
    "\{info.name} appeared",
  ))
}
```

The handle unsubscribes the same way [every other
subscription](/cookbook/events/) does.

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
