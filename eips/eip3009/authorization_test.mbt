///|
/// The example every test here shares: USDC on mainnet, moving one dollar.
/// The hashes it is checked against were computed outside this SDK — the type
/// hashes are the constants USDC's own `EIP3009.sol` carries, and the domain
/// separator and digest were built with `cast` — so what follows is a check
/// against EIP-3009 rather than against yesterday's version of this file.
fn usdc() -> @eip712.TypedDataDomain raise @types.CodecError {
  @eip3009.domain(
    name="USD Coin",
    chain_id=@types.ChainId::mainnet(),
    token=@types.Address::from_string(
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    ),
  )
}

///|
/// The two parties every fixture here uses, spelled once. They are EIP-712's
/// own example addresses, so nothing about them is EIP-3009's.
fn alice() -> @types.Address raise @types.CodecError {
  @types.Address::from_string("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826")
}

///|
fn bob() -> @types.Address raise @types.CodecError {
  @types.Address::from_string("0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB")
}

///|
/// The nonce every fixture is signed against. A real one comes off
/// `draw_nonce`; this one is fixed so the hashes checked against `cast` are
/// fixed too.
fn nonce() -> @types.Hex raise @types.CodecError {
  @types.Hex::from_string(
    "0x0000000000000000000000000000000000000000000000000000000000000001",
  )
}

///|
fn one_dollar() -> @eip3009.Authorization raise @types.CodecError {
  @eip3009.Authorization::new(
    from=alice(),
    to=bob(),
    value=1000000,
    valid_before=2000000000,
    nonce=nonce(),
  )
}

///|
/// The document as `eth_signTypedData_v4` receives it. The amounts are decimal
/// strings, which is what keeps a `uint256` exact past 2^53.
test "transfer document" {
  inspect(
    one_dollar().transfer_typed_data(usdc()).to_json().stringify(),
    content=(
      #|{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"TransferWithAuthorization":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"value","type":"uint256"},{"name":"validAfter","type":"uint256"},{"name":"validBefore","type":"uint256"},{"name":"nonce","type":"bytes32"}]},"primaryType":"TransferWithAuthorization","domain":{"name":"USD Coin","version":"1","chainId":1,"verifyingContract":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"},"message":{"from":"0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826","to":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","value":"1000000","validAfter":"0","validBefore":"2000000000","nonce":"0x0000000000000000000000000000000000000000000000000000000000000001"}}
    ),
  )
}

///|
/// `encodeType`, and with it the type hash USDC's `EIP3009.sol` declares as
/// `TRANSFER_WITH_AUTHORIZATION_TYPEHASH`. The member order is part of the
/// hash, so this is the test that would catch a field moved.
test "transfer type hash" {
  let document = one_dollar().transfer_typed_data(usdc())
  inspect(
    document.encode_type("TransferWithAuthorization"),
    content="TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)",
  )
  inspect(
    document.type_hash("TransferWithAuthorization").to_string(),
    content="0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267",
  )
}

///|
/// `RECEIVE_WITH_AUTHORIZATION_TYPEHASH`. The members are the transfer's, so
/// only the name differs — and that is enough to make the two signatures
/// unusable in each other's place, which is the whole point of the second form.
test "receive type hash" {
  let auth = one_dollar()
  let usdc = usdc()
  let document = auth.receive_typed_data(usdc)
  inspect(
    document.type_hash("ReceiveWithAuthorization").to_string(),
    content="0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8",
  )
  // the *same* authorization, under the other name
  assert_true(document.digest() != auth.transfer_typed_data(usdc).digest())
}

///|
/// `CANCEL_AUTHORIZATION_TYPEHASH`, over the two members cancelling needs.
test "cancel document" {
  let auth = one_dollar()
  let cancel = @eip3009.CancelAuthorization::new(
    authorizer=auth.from(),
    nonce=auth.nonce(),
  )
  let document = cancel.typed_data(usdc())
  inspect(
    document.encode_type("CancelAuthorization"),
    content="CancelAuthorization(address authorizer,bytes32 nonce)",
  )
  inspect(
    document.type_hash("CancelAuthorization").to_string(),
    content="0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429",
  )
  inspect(
    document.to_json().stringify(),
    content=(
      #|{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"CancelAuthorization":[{"name":"authorizer","type":"address"},{"name":"nonce","type":"bytes32"}]},"primaryType":"CancelAuthorization","domain":{"name":"USD Coin","version":"1","chainId":1,"verifyingContract":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"},"message":{"authorizer":"0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826","nonce":"0x0000000000000000000000000000000000000000000000000000000000000001"}}
    ),
  )
}

///|
/// The digest a wallet signs, end to end: the domain separator over the token's
/// four fields, and `0x19 0x01 ‖ domainSeparator ‖ hashStruct` over them.
test "transfer digest" {
  let document = one_dollar().transfer_typed_data(usdc())
  inspect(
    document.domain_separator().to_string(),
    content="0x53af746ecdec49e555bd241cdef7a4e3f4012770364b774a3f9b60cc4ae63717",
  )
  inspect(
    document.hash_struct().to_string(),
    content="0x7850f6e5f6352c45a553a6b77994f8aec905a47860cf49f0fec1056a05398ce7",
  )
  inspect(
    document.digest().to_string(),
    content="0xc8d82f93b47083b1f74e29a59f07bd125dea1859b418afe0a550ad8c67b14d38",
  )
}

///|
/// The submitter has to read the authorization back to build its own call, so
/// what went in comes out.
test "authorization reads back" {
  let auth = one_dollar()
  inspect(
    auth.from().to_string(),
    content="0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826",
  )
  inspect(
    auth.to().to_string(),
    content="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  inspect(auth.value(), content="1000000")
  inspect(auth.valid_after(), content="0")
  inspect(auth.valid_before(), content="2000000000")
  inspect(
    auth.nonce().to_string(),
    content="0x0000000000000000000000000000000000000000000000000000000000000001",
  )
}

///|
/// A window that closes before it opens can never be used, so it is refused
/// where it is spelled rather than on chain.
test "error empty validity window" {
  try
    @eip3009.Authorization::new(
      from=alice(),
      to=bob(),
      value=1,
      valid_after=2000000000,
      valid_before=1000000000,
      nonce=nonce(),
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(
        m,
        content="authorization is valid between 2000000000 and 1000000000, which is never",
      )
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The nonce is what the token marks as used, and it marks a `bytes32`.
test "error short nonce" {
  try
    @eip3009.CancelAuthorization::new(
      authorizer=alice(),
      nonce=@types.Hex::from_string("0x01"),
    )
    |> ignore
  catch {
    @types.InvalidLength(m) =>
      inspect(m, content="authorization nonce must be 32 bytes: 0x01")
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// An amount past `uint256` would be silently truncated by the token, so it is
/// refused here.
test "error value past uint256" {
  try
    @eip3009.Authorization::new(
      from=alice(),
      to=bob(),
      value=1N << 256,
      valid_before=2000000000,
      nonce=nonce(),
    )
    |> ignore
  catch {
    @types.InvalidValue(_) => ()
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
