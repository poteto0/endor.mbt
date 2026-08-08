---
title: Events
description: The three EIP-1193 events, and why EventSource is a separate trait.
---

# Events

| Function                                    | EIP-1193 event    | Handler receives          |
| ------------------------------------------- | ----------------- | ------------------------- |
| `@provider.on_accounts_changed(e, handler)` | `accountsChanged` | `Array[@endor.Address]`   |
| `@provider.on_chain_changed(e, handler)`    | `chainChanged`    | `@endor.ChainId`          |
| `@provider.on_disconnect(e, handler)`       | `disconnect`      | `@provider.ProviderError` |

All three take an `@provider.EventSource` — a provider that can push, which
`BrowserProvider` and `MockProvider` both are — and return an
`@provider.Subscription`, a plain value with no framework attached whose
`unsubscribe()` stops that one handler and is safe to call twice.

[React to wallet changes](/cookbook/events/) is the worked example, with a demo.

## EventSource is a separate trait

Deliberately: a transport can answer RPC without being able to push anything
back, and the typed RPC helpers stay usable against one that cannot.
[`@http.HttpProvider`](/cookbook/http-rpc/) is that case in the SDK itself — it
implements `Provider` and not `EventSource`, because a POST endpoint has no
`accountsChanged` to send and nobody behind it to change an account. Passing one
to a helper on this page is a compile error rather than a subscription that
never fires. Anything the three helpers do not cover is reachable with the raw
`EventSource::subscribe(event~, handler~)`, which hands the payload over as
`Json`.

## Subscribing reads no initial value

Because the SDK is stateless, `on_accounts_changed` fires when the account
*changes*, so a dapp reads its starting point with `@provider.accounts` /
`@provider.chain_id` and holds it.

## A malformed payload is dropped

A `chainChanged` that is not a hex quantity, a `disconnect` with no numeric
`code`: the handler is not called and nothing is raised, since an event arrives
outside any call the dapp made and has nowhere to raise to. The subscription
stays live and the next well-formed event is delivered normally.

## Empty accounts is not disconnect

`accountsChanged` with an empty array is how EIP-1193 says the user revoked the
dapp's permission. `disconnect` is the provider losing its connection to every
chain, and carries a `ProviderRpcError` (`{code, message}`) mapped through
`ProviderError::from_code`, typically to `Disconnected` (4900).

## Not every wallet has them

`@browser.BrowserProvider::has_events()` reports whether the injected object
exposes `on` / `removeListener`. Subscribing to one that does not is inert rather
than fatal — the handler simply never fires, and `unsubscribe` is still safe.
