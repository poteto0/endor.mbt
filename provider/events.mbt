///|
/// A provider that can also be *subscribed to*: one that implements the
/// EIP-1193 event API (`on` / `removeListener`) on top of `request`.
///
/// Deliberately **not** part of `Provider`, since a transport can answer RPC
/// without being able to push. The single method here is the raw one; prefer the
/// typed helpers below and reach for `subscribe` only for an event they miss.
///
/// ```
/// // Any `EventSource` can be driven by the typed helpers:
/// fn watch[E : @provider.EventSource](e : E) -> @provider.Subscription {
///   @provider.on_chain_changed(e, chain => println("chain: \{chain}"))
/// }
/// ```
pub(open) trait EventSource {
  /// Register `handler` for the EIP-1193 event named `event`, and return the
  /// handle that cancels it. `handler` receives the event payload as raw JSON.
  fn subscribe(Self, event~ : String, handler~ : (Json) -> Unit) -> Subscription
}

///|
/// The handle returned by every subscription: calling `unsubscribe` stops
/// delivery to that one handler and leaves any other subscription alone.
///
/// It is a plain value with no framework attached, so a UI layer can wrap it
/// into whatever its own lifecycle wants (an effect cleanup, a `defer`, a
/// disposer list) without the SDK depending on that layer.
///
/// ```mbt check
/// test "doc: subscription unsubscribes once" {
///   let fired = []
///   let sub = @provider.Subscription::new(() => fired.push("cancelled"))
///   sub.unsubscribe()
///   sub.unsubscribe() // idempotent: cancelling twice is safe
///   inspect(fired.length(), content="1")
/// }
/// ```
pub struct Subscription {
  priv mut cancel : (() -> Unit)?
}

///|
/// Build a subscription from the thunk that cancels it. This is what an
/// `EventSource` implementation returns from `subscribe`; callers of the typed
/// helpers get one back rather than building it.
pub fn Subscription::new(cancel : () -> Unit) -> Subscription {
  Subscription::{ cancel: Some(cancel) }
}

///|
/// Stop delivering the subscribed event to this handler.
///
/// Idempotent: the cancel thunk runs at most once, so calling it twice — or
/// after the page already tore the provider down — is safe and does nothing the
/// second time.
pub fn Subscription::unsubscribe(self : Subscription) -> Unit {
  match self.cancel {
    Some(cancel) => {
      self.cancel = None
      cancel()
    }
    None => ()
  }
}

///|
/// Subscribe to `accountsChanged`: the wallet switched accounts, or the user
/// disconnected the dapp.
///
/// The handler receives the full authorized list, most-recently-selected first,
/// and an **empty array means disconnected**. The SDK caches nothing, so a dapp
/// that needs the current account holds it itself.
///
/// ```mbt check
/// test "doc: watch accounts" {
///   let mock = @provider.MockProvider::new()
///   let seen = []
///   let sub = @provider.on_accounts_changed(mock, accounts => {
///     seen.push(accounts.length())
///   })
///   mock.emit(
///     event="accountsChanged",
///     payload=["0x1111111111111111111111111111111111111111"].to_json(),
///   )
///   sub.unsubscribe()
///   inspect(seen.length(), content="1")
///   inspect(seen[0], content="1")
/// }
/// ```
pub fn[E : EventSource] on_accounts_changed(
  source : E,
  handler : (Array[@types.Address]) -> Unit,
) -> Subscription {
  on_decoded(
    source,
    event="accountsChanged",
    decode=payload => {
      Some(@types.Address::array_from_json(payload)) catch {
        _ => None
      }
    },
    handler,
  )
}

///|
/// Subscribe to `event`, decoding its payload before the handler sees it. A
/// payload the decoder answers `None` for is dropped — the one place the typed
/// helpers' drop-on-malformed policy is implemented.
fn[E : EventSource, T] on_decoded(
  source : E,
  event~ : String,
  decode~ : (Json) -> T?,
  handler : (T) -> Unit,
) -> Subscription {
  source.subscribe(event~, handler=payload => {
    if decode(payload) is Some(value) {
      handler(value)
    }
  })
}

///|
/// Subscribe to `chainChanged`: the wallet moved to a different chain, either on
/// its own or because `switch_chain` asked it to.
///
/// EIP-1193 recommends dapps reload on this event, since anything read from the
/// old chain is now about a different network. As with accounts, the SDK caches
/// nothing, and a payload that is not a hex quantity is dropped.
///
/// ```mbt check
/// test "doc: watch chain" {
///   let mock = @provider.MockProvider::new()
///   let seen = []
///   let sub = @provider.on_chain_changed(mock, chain => {
///     seen.push(chain.to_uint64())
///   })
///   mock.emit(event="chainChanged", payload="0x89".to_json())
///   sub.unsubscribe()
///   inspect(seen[0], content="137")
/// }
/// ```
pub fn[E : EventSource] on_chain_changed(
  source : E,
  handler : (@types.ChainId) -> Unit,
) -> Subscription {
  on_decoded(
    source,
    event="chainChanged",
    decode=payload => {
      Some(@types.ChainId::from_json(payload)) catch {
        _ => None
      }
    },
    handler,
  )
}

///|
/// Subscribe to `disconnect`: the provider lost its connection to every chain
/// and can no longer answer requests until it reconnects.
///
/// EIP-1193 carries a `ProviderRpcError` here, so the handler receives it
/// through the same `ProviderError::from_code` mapping. This is not the "user
/// disconnected the dapp" event — that one is `accountsChanged` with `[]`.
///
/// ```mbt check
/// test "doc: watch disconnect" {
///   let mock = @provider.MockProvider::new()
///   let seen = []
///   let sub = @provider.on_disconnect(mock, error => seen.push(error))
///   mock.emit(event="disconnect", payload={
///     "code": 4900,
///     "message": "disconnected",
///   })
///   sub.unsubscribe()
///   inspect(seen[0], content="Disconnected")
/// }
/// ```
pub fn[E : EventSource] on_disconnect(
  source : E,
  handler : (ProviderError) -> Unit,
) -> Subscription {
  on_decoded(
    source,
    event="disconnect",
    decode=ProviderError::from_json,
    handler,
  )
}
