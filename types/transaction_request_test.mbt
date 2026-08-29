///|
/// The sender every transaction test signs with. `address` and `calldata` come
/// from the call-request tests: same package, same helpers.
fn sender() -> @types.Address {
  address("0x52908400098527886E0F7030069857D2E4169EE7")
}

///|
test "transaction request encodes every field it was given" {
  let req = @types.TransactionRequest::new(
    sender(),
    to=address("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
    value=@types.Wei::from_int(1000),
    data=calldata("0x70a08231"),
    gas=@types.Quantity::new(21000),
    nonce=@types.Quantity::new(7),
    fee=Legacy(gas_price=@types.Wei::from_int(255)),
  )
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","to":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","value":"0x3e8","data":"0x70a08231","gas":"0x5208","nonce":"0x7","gasPrice":"0xff"}
    ),
  )
}

///|
/// Absent fields are omitted rather than sent as `null`: that is how the RPC
/// spells "the wallet decides". A nonce of zero, on the other hand, is a value
/// that was given — the first transaction of an account — so it is sent.
test "transaction request omits the fields it was not given" {
  inspect(
    @types.TransactionRequest::new(sender()).to_json().stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7"}
    ),
  )
  inspect(
    @types.TransactionRequest::new(sender(), nonce=@types.Quantity::new(0))
    .to_json()
    .stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","nonce":"0x0"}
    ),
  )
}

///|
/// A transaction with no `to` deploys the contract in `data`, so an absent `to`
/// has to stay absent rather than being filled in with a zero address — which
/// would send the funds to the burn address instead.
test "transaction request without a recipient is a deployment" {
  let deploy = @types.TransactionRequest::new(
    sender(),
    data=calldata("0x600a600c600039600a6000f3"),
  )
  inspect(
    deploy.to_json().stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","data":"0x600a600c600039600a6000f3"}
    ),
  )
}

///|
/// The three fee modes are exactly the three geth accepts: none (it defaults
/// the transaction to EIP-1559 on a London chain), both EIP-1559 fields, or
/// `gasPrice` alone. Sending `gasPrice` together with either EIP-1559 field is
/// the one combination geth rejects, and `Fee` cannot express it.
test "fee mode decides which fee fields go on the wire" {
  let auto = @types.TransactionRequest::new(sender()).to_json().stringify()
  inspect(auto.contains("gasPrice"), content="false")
  inspect(auto.contains("maxFeePerGas"), content="false")
  inspect(
    @types.TransactionRequest::new(
      sender(),
      fee=Eip1559(
        max_fee_per_gas=@types.Wei::from_int(100),
        max_priority_fee_per_gas=@types.Wei::from_int(1),
      ),
    )
    .to_json()
    .stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","maxFeePerGas":"0x64","maxPriorityFeePerGas":"0x1"}
    ),
  )
  let legacy = @types.TransactionRequest::new(
      sender(),
      fee=Legacy(gas_price=@types.Wei::from_int(100)),
    )
    .to_json()
    .stringify()
  inspect(legacy.contains("maxFeePerGas"), content="false")
  inspect(legacy.contains("\"gasPrice\":\"0x64\""), content="true")
}

///|
/// An empty list is left out rather than sent as `[]`, which the omit test
/// above pins along with every other absent field.
test "an access list is sent only when it declares something" {
  let req = @types.TransactionRequest::new(
    sender(),
    to=address("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
    access_list=[
      @types.AccessListItem::new(
        address("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
        storage_keys=[@types.Hex::from_string(SLOT_7)],
      ),
    ],
  )
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","to":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","accessList":[{"address":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","storageKeys":["0x0000000000000000000000000000000000000000000000000000000000000007"]}]}
    ),
  )
}

///|
/// The list is copied in, so the caller's array is not the request's.
test "the request's access list cannot be changed afterwards" {
  let list = [@types.AccessListItem::new(sender())]
  let req = @types.TransactionRequest::new(sender(), access_list=list)
  let before = req.to_json().stringify()
  list.clear()
  assert_eq(req.to_json().stringify(), before)
}

///|
/// An authorization list is what makes a request a 7702 one — a request names
/// no type byte — so it goes out under `authorizationList`, and an empty one
/// is left out like every other absent field.
test "an authorization list is sent only when it delegates something" {
  let signed = @types.SignedAuthorization::from_json({
    "chainId": "0x1",
    "address": "0x8617e340b3d01fa5f11f306f4090fd50e238070d",
    "nonce": "0x8",
    "yParity": "0x1",
    "r": "0x1",
    "s": "0x2",
  })
  inspect(
    @types.TransactionRequest::new(
      sender(),
      to=address("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
      authorization_list=[signed],
    )
    .to_json()
    .stringify(),
    content=(
      #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","to":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","authorizationList":[{"chainId":"0x1","address":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","nonce":"0x8","yParity":"0x1","r":"0x0000000000000000000000000000000000000000000000000000000000000001","s":"0x0000000000000000000000000000000000000000000000000000000000000002"}]}
    ),
  )
  // and the list is copied in, as the access list is
  let list = [signed]
  let req = @types.TransactionRequest::new(sender(), authorization_list=list)
  let before = req.to_json().stringify()
  list.clear()
  assert_eq(req.to_json().stringify(), before)
}
