///|
/// The example every test here shares: USDC on mainnet, approving one dollar.
/// The hashes it is checked against were computed outside this SDK, with
/// `cast` — and the type hash so computed is byte for byte the
/// `PERMIT_TYPEHASH` constant every EIP-2612 token carries, which is what makes
/// the rest of them a check against EIP-2612 rather than against yesterday's
/// version of this file.
///
/// `version="2"` is not a typo and not an alternative spelling: USDC's domain
/// says `"2"`, most other tokens say `"1"`, and the two produce different
/// signatures. It is the mistake `check_separator` exists to catch, so the fixture
/// is the token that makes it.
fn usdc() -> @eip712.TypedDataDomain raise @types.CodecError {
  @eip2612.domain(
    name="USD Coin",
    version="2",
    chain_id=@types.ChainId::mainnet(),
    token=@types.Address::from_string(
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    ),
  )
}

///|
/// The two parties every fixture here uses, spelled once. They are EIP-712's
/// own example addresses, so nothing about them is EIP-2612's.
fn alice() -> @types.Address raise @types.CodecError {
  @types.Address::from_string("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826")
}

///|
fn bob() -> @types.Address raise @types.CodecError {
  @types.Address::from_string("0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB")
}

///|
fn one_dollar() -> @eip2612.Permit raise @types.CodecError {
  @eip2612.Permit::new(
    owner=alice(),
    spender=bob(),
    value=1000000,
    nonce=0,
    deadline=2000000000,
  )
}

///|
/// The document as `eth_signTypedData_v4` receives it. The amounts are decimal
/// strings, which is what keeps a `uint256` exact past 2^53.
test "permit document" {
  inspect(
    one_dollar().typed_data(usdc()).to_json().stringify(),
    content=(
      #|{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Permit":[{"name":"owner","type":"address"},{"name":"spender","type":"address"},{"name":"value","type":"uint256"},{"name":"nonce","type":"uint256"},{"name":"deadline","type":"uint256"}]},"primaryType":"Permit","domain":{"name":"USD Coin","version":"2","chainId":1,"verifyingContract":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"},"message":{"owner":"0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826","spender":"0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","value":"1000000","nonce":"0","deadline":"2000000000"}}
    ),
  )
}

///|
/// The member list in the order the standard fixes, and the hash of it: this is
/// `PERMIT_TYPEHASH` as OpenZeppelin's `ERC20Permit`, USDC and Uniswap all
/// declare it. A member renamed or reordered here changes this hash and every
/// signature with it.
test "permit type hash is the standard's" {
  let document = one_dollar().typed_data(usdc())
  inspect(
    document.encode_type("Permit"),
    content="Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)",
  )
  inspect(
    document.type_hash("Permit"),
    content="0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9",
  )
}

///|
/// What the wallet signs, and what the token's `permit` recovers the signer
/// from.
test "permit digest" {
  let document = one_dollar().typed_data(usdc())
  inspect(
    document.hash_struct(),
    content="0xa7f888d616c07ae03fb7421b092d3fe32af38363be874a32469ad172902d3fde",
  )
  inspect(
    document.digest(),
    content="0xd4cc1c99d885bb0fb9433a70b0ac50d01e44d95d094f1cf08bcbffcc83e23310",
  )
}

///|
/// The domain separator on its own — the same hash the token publishes as
/// `DOMAIN_SEPARATOR()`, reachable before any message exists.
test "domain separator" {
  inspect(
    usdc().separator(),
    content="0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335",
  )
}

///|
/// The check passes against what the token would answer.
test "check_separator accepts the token's own" {
  usdc().check_separator(
    on_chain=@types.Hex::from_string(
      "0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335",
    ),
  )
}

///|
/// And refuses the `version="1"` domain, which is what a caller gets by taking
/// the default on a token that says `"2"`. Nothing about that document looks
/// wrong: it signs, it displays, and the token rejects it.
test "check_separator refuses the wrong version" {
  let wrong = @eip2612.domain(
    name="USD Coin",
    chain_id=@types.ChainId::mainnet(),
    token=@types.Address::from_string(
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    ),
  )
  inspect(
    wrong.separator(),
    content="0x53af746ecdec49e555bd241cdef7a4e3f4012770364b774a3f9b60cc4ae63717",
  )
  try
    wrong.check_separator(
      on_chain=@types.Hex::from_string(
        "0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335",
      ),
    )
  catch {
    @types.InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The members are readable back out, which is what the submitter's
/// `permit(owner, spender, value, deadline, v, r, s)` is built from — note that
/// the nonce is *not* an argument to that call: the token reads its own.
test "the members are readable" {
  let permit = one_dollar()
  assert_eq(permit.owner(), alice())
  assert_eq(permit.spender(), bob())
  assert_eq(permit.value(), 1000000)
  assert_eq(permit.nonce(), 0)
  assert_eq(permit.deadline(), 2000000000)
}

///|
/// Each of the three numbers is a `uint256`, and is refused where it is spelled
/// rather than at signing time. The message names which one, since all three
/// go through the same check.
test "a number too wide for a word is refused" {
  try
    @eip2612.Permit::new(
      owner=alice(),
      spender=bob(),
      value=BigInt::from_int(1) << 256,
      nonce=0,
      deadline=1,
    )
    |> ignore
  catch {
    @types.InvalidLength(m) =>
      inspect(
        m,
        content="permit value does not fit uint256: 115792089237316195423570985008687907853269984665640564039457584007913129639936",
      )
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A permit that never expires is spelled, not defaulted: `type(uint256).max`
/// is the standard's own way of saying it, and it is the widest value the
/// deadline accepts.
test "the widest deadline is accepted" {
  let forever = (BigInt::from_int(1) << 256) - 1
  let permit = @eip2612.Permit::new(
    owner=alice(),
    spender=bob(),
    value=1,
    nonce=0,
    deadline=forever,
  )
  inspect(
    permit
    .typed_data(usdc())
    .to_json()
    .stringify()
    .contains(
      "115792089237316195423570985008687907853269984665640564039457584007913129639935",
    ),
    content="true",
  )
}
