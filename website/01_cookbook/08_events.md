---
title: React to wallet changes
description: Three EIP-1193 events, plain callbacks, and a Subscription your own lifecycle owns.
islands:
  - connect
---

# React to wallet changes

Every read answers for the wallet's state *at that moment*, and the user can
change it from under you at any time. These three events are how you learn your
answers went stale.

The demo below is the [connect](./connect/) one again. Switch account in your
extension, or switch chain from another tab, and watch the fields follow without
the page being touched.

<Island name="connect" trigger="load" />

## Subscribing

```moonbit
fn watch(wallet : @browser.BrowserProvider) -> @provider.Subscription {
  // accountsChanged: the user switched account, or revoked the dapp's access
  let sub = @provider.on_accounts_changed(wallet, accounts => match accounts.get(
      0,
    ) {
    Some(addr) => println("now \{addr}") // most recently selected first
    None => println("disconnected") // an empty array ⇒ permission revoked
  })
  // chainChanged: everything read from the old chain is about another one now
  let _ = @provider.on_chain_changed(wallet, chain => println("chain \{chain.to_hex()}"))
  // disconnect: a ProviderRpcError, mapped like any other wallet-side failure
  let _ = @provider.on_disconnect(wallet, error => println("gone: \{error}"))
  sub // `sub.unsubscribe()` stops that one handler; calling it twice is safe
}
```

| Function                                    | EIP-1193 event    | Handler receives          |
| ------------------------------------------- | ----------------- | ------------------------- |
| `@provider.on_accounts_changed(e, handler)` | `accountsChanged` | `Array[@endor.Address]`   |
| `@provider.on_chain_changed(e, handler)`    | `chainChanged`    | `@endor.ChainId`          |
| `@provider.on_disconnect(e, handler)`       | `disconnect`      | `@provider.ProviderError` |

Each takes a plain callback and hands back a `Subscription`: no UI framework,
nothing to wire up, just a thunk your own lifecycle can call when it tears down.

## Subscribing reads no initial value

This is the part that surprises people. The SDK caches nothing, so
`on_accounts_changed` fires when the account *changes* and not when you start
listening. The starting point is a call you make:

```moonbit
async fn start_watching(
  wallet : @browser.BrowserProvider,
  hold : (@endor.Address?) -> Unit,
) -> @provider.Subscription raise {
  // the starting point, read once — `accounts` never prompts
  hold(@provider.accounts(wallet).get(0))
  // and every change after that
  @provider.on_accounts_changed(wallet, accounts => hold(accounts.get(0)))
}
```

## Empty is not disconnected

`accountsChanged` with an empty array is how EIP-1193 says the user revoked this
page's permission. It is a different thing from `disconnect`, which is the
provider losing its connection to every chain:

```moonbit
fn tell_them_apart(
  wallet : @browser.BrowserProvider,
) -> Array[@provider.Subscription] {
  [
    @provider.on_accounts_changed(wallet, accounts => if accounts.is_empty() {
      // still connected to a wallet; it just will not tell us who any more
      println("access revoked — ask for permission again")
    } else {
      println("switched to \{accounts[0]}")
    }),
    @provider.on_disconnect(wallet, error =>
      // the provider itself is gone. Typically Disconnected (4900).
      println("the provider went away: \{error}")),
  ]
}
```

## Tearing down

```moonbit
fn stop(subscriptions : Array[@provider.Subscription]) -> Unit {
  for sub in subscriptions {
    // safe to call twice, so a teardown that runs twice is not a bug
    sub.unsubscribe()
  }
}
```

## A malformed event is dropped

An event arrives outside any call you made, so there is nowhere to raise to. A
payload that fails to decode — a `chainChanged` that is not a hex quantity, a
`disconnect` with no numeric `code` — does not call the handler and does not
raise. The subscription stays live and the next well-formed event is delivered
normally.

## Not every wallet pushes events

```moonbit
fn is_it_worth_subscribing(wallet : @browser.BrowserProvider) -> Bool {
  // whether the injected object exposes `on` / `removeListener` at all
  wallet.has_events()
}
```

Subscribing to a wallet that does not is inert rather than fatal: the handler
never fires and `unsubscribe` is still safe. Worth checking anyway, so the UI can
say the fields will only update on a click — which is what the demo above does.

## Anything else

`EventSource::subscribe(event~, handler~)` is the raw form, and hands the payload
over as `Json`. `EventSource` is deliberately a separate trait from `Provider`: a
transport can answer RPC without being able to push anything back, and the typed
RPC helpers stay usable against one that cannot.
