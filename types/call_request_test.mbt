///|
/// The contract every call test is aimed at. Parsing it cannot fail, so the
/// tests below spend no lines on the codec they are not exercising.
fn call_target() -> @types.Address {
  address("0x52908400098527886E0F7030069857D2E4169EE7")
}

///|
fn address(s : String) -> @types.Address {
  @types.Address::from_string(s) catch {
    e => abort("bad test address: \{e}")
  }
}

///|
fn calldata(s : String) -> @types.Hex {
  @types.Hex::from_string(s) catch {
    e => abort("bad test calldata: \{e}")
  }
}

///|
test "call request encodes every field it was given" {
  let req = @types.CallRequest::new(
    call_target(),
    from=address("0x52908400098527886E0F7030069857D2E4169EE8"),
    data=calldata("0x70a08231"),
    value=@types.Wei::from_int(255),
  )
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"to":"0x52908400098527886e0f7030069857d2e4169ee7","from":"0x52908400098527886e0f7030069857d2e4169ee8","data":"0x70a08231","value":"0xff"}
    ),
  )
}

///|
/// The optional fields are left out rather than sent as `null` — that is how the
/// RPC spells "unspecified", and a wallet reading `null` as a value would reject
/// the request.
test "call request omits the fields it was not given" {
  let req = @types.CallRequest::new(call_target())
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"to":"0x52908400098527886e0f7030069857d2e4169ee7"}
    ),
  )

  // zero wei is a value that was given, so it is sent
  let req = @types.CallRequest::new(call_target(), value=@types.Wei::zero())
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"to":"0x52908400098527886e0f7030069857d2e4169ee7","value":"0x0"}
    ),
  )

  // empty calldata likewise: "0x" means a call with no arguments, not no data
  let req = @types.CallRequest::new(call_target(), data=calldata("0x"))
  inspect(
    req.to_json().stringify(),
    content=(
      #|{"to":"0x52908400098527886e0f7030069857d2e4169ee7","data":"0x"}
    ),
  )
}
