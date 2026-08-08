///|
/// A valid 20-byte address, spelled out once so the payloads below stay short.
let alice : String = "0x1111111111111111111111111111111111111111"

///|
let bob : String = "0x2222222222222222222222222222222222222222"

///|
test "accounts changed decodes the payload" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_accounts_changed(mock, accounts => seen.push(accounts))
  mock.emit(event="accountsChanged", payload=[alice, bob].to_json())
  inspect(seen.length(), content="1")
  inspect(seen[0].length(), content="2")
  inspect(seen[0][0], content="0x1111111111111111111111111111111111111111")
  inspect(seen[0][1], content="0x2222222222222222222222222222222222222222")
  // EIP-1193: an empty list is the user revoking permission, and reaches the
  // handler as itself rather than as a dropped payload
  mock.emit(event="accountsChanged", payload=Json::array([]))
  inspect(seen.length(), content="2")
  inspect(seen[1].length(), content="0")
}

///|
test "chain changed decodes the hex quantity" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_chain_changed(mock, chain => seen.push(chain))
  mock.emit(event="chainChanged", payload="0x89".to_json())
  inspect(seen.length(), content="1")
  inspect(seen[0], content="ChainId(137)")
}

///|
test "disconnect maps 4900 onto a typed error" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_disconnect(mock, error => seen.push(error))
  mock.emit(event="disconnect", payload={
    "code": 4900,
    "message": "disconnected from all chains",
  })
  inspect(seen.length(), content="1")
  inspect(seen[0], content="Disconnected")
}

///|
test "unsubscribe stops delivery to that handler only, in registration order" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let kept = @provider.on_chain_changed(mock, _ => seen.push("kept"))
  let dropped = @provider.on_chain_changed(mock, _ => seen.push("dropped"))
  mock.emit(event="chainChanged", payload="0x1".to_json())
  dropped.unsubscribe()
  mock.emit(event="chainChanged", payload="0x1".to_json())
  debug_inspect(
    seen,
    content=(
      #|["kept", "dropped", "kept"]
    ),
  )
  kept.unsubscribe()
  mock.emit(event="chainChanged", payload="0x1".to_json())
  inspect(seen.length(), content="3")
}

///|
test "unsubscribing twice is safe" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let other = @provider.on_chain_changed(mock, _ => seen.push("other"))
  let sub = @provider.on_chain_changed(mock, _ => seen.push("sub"))
  sub.unsubscribe()
  // the second call must neither fail nor remove anyone else's listener
  sub.unsubscribe()
  mock.emit(event="chainChanged", payload="0x1".to_json())
  debug_inspect(
    seen,
    content=(
      #|["other"]
    ),
  )
  other.unsubscribe()
}

///|
test "a malformed accounts payload is dropped" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_accounts_changed(mock, accounts => seen.push(accounts))
  mock.emit(event="accountsChanged", payload="not an array".to_json())
  mock.emit(event="accountsChanged", payload=["0xnot-an-address"].to_json())
  mock.emit(event="accountsChanged", payload=Json::null())
  inspect(seen.length(), content="0")
  // still live: a bad payload drops that event, it does not cancel anything
  mock.emit(event="accountsChanged", payload=[alice].to_json())
  inspect(seen.length(), content="1")
}

///|
test "a malformed chain payload is dropped" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_chain_changed(mock, chain => seen.push(chain))
  mock.emit(event="chainChanged", payload="nonsense".to_json())
  mock.emit(event="chainChanged", payload=Json::number(1))
  inspect(seen.length(), content="0")
}

///|
test "a malformed disconnect payload is dropped" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_disconnect(mock, error => seen.push(error))
  mock.emit(event="disconnect", payload=Json::null())
  mock.emit(event="disconnect", payload={ "message": "no code" })
  mock.emit(event="disconnect", payload={ "code": "4900" })
  inspect(seen.length(), content="0")
  // a code with no message still decodes; the message is simply empty
  mock.emit(event="disconnect", payload={ "code": 4900 })
  inspect(seen[0], content="Disconnected")
}

///|
test "an event nobody subscribed to is ignored" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let _ = @provider.on_chain_changed(mock, chain => seen.push(chain))
  mock.emit(event="accountsChanged", payload=[alice].to_json())
  mock.emit(event="message", payload=Json::null())
  inspect(seen.length(), content="0")
}

///|
test "subscribe reaches an event the typed helpers do not cover" {
  let mock = @provider.MockProvider::new()
  let seen = []
  let sub = mock.subscribe(event="message", handler=payload => {
    seen.push(payload.stringify())
  })
  mock.emit(event="message", payload={ "type": "eth_subscription" })
  sub.unsubscribe()
  mock.emit(event="message", payload={ "type": "eth_subscription" })
  debug_inspect(
    seen,
    content=(
      #|["{\"type\":\"eth_subscription\"}"]
    ),
  )
}
