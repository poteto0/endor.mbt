///|
/// A token nobody deployed, and the three accounts around one authorization:
/// the holder who signs, the payee, and the relayer who pays the gas.
fn token() -> @types.Address {
  address("0x431D5dfF03120AFA4bDf332c61A6e1766eF37BDB")
}

///|
fn holder() -> @types.Address {
  address("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
}

///|
fn payee() -> @types.Address {
  address("0x000000000000000000000000000000000000dEaD")
}

///|
fn relayer() -> @types.Address {
  address("0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
}

///|
fn address(s : String) -> @types.Address {
  @types.Address::from_string(s) catch {
    e => abort("bad test address: \{e}")
  }
}

///|
/// The authorization these tests submit: 1000 JPYC, valid for an hour, at a
/// nonce spelled out rather than drawn so the calldata is a fixed string.
fn authorization() -> @eip3009.Authorization {
  @eip3009.Authorization::new(
    from=holder(),
    to=payee(),
    value=BigInt::from_string("1000000000000000000000"),
    valid_before=2000000000,
    nonce=nonce(),
  ) catch {
    e => abort("bad test authorization: \{e}")
  }
}

///|
fn nonce() -> @types.Hex {
  @types.Hex::from_string(
    "0x00000000000000000000000000000000000000000000000000000000000000ff",
  ) catch {
    e => abort("bad test nonce: \{e}")
  }
}

///|
/// A real signature, made here rather than pasted: the point of the tests below
/// is that `(v, r, s)` reach the calldata as the token wants them, and a
/// hand-written 65 bytes would not be a signature at all.
fn signature() -> @types.Hex {
  @types.Hex::from_bytes(signed().to_bytes(v_offset=27))
}

///|
/// The same signature with a `v` of `0` or `1` — how a typed transaction spells
/// it, and the other thing a wallet may answer with.
fn raw_signature() -> @types.Hex {
  @types.Hex::from_bytes(signed().to_bytes())
}

///|
fn signed() -> @secp256k1.Signature {
  try {
    let key = @secp256k1.PrivateKey::from_bytes(
      @types.Hex::from_string(
        "0x289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
      ).to_bytes(),
    )
    key.sign(Bytes::make(32, b'\x11'))
  } catch {
    e => abort("bad test signature: \{e}")
  }
}

///|
/// A provider that answers one `eth_call` with `data`.
fn answering(data : String) -> @provider.MockProvider {
  @provider.MockProvider::new().on(
    method_name="eth_call",
    response=Json::string(data),
  )
}

///|
/// The calldata the last call carried — the selector and the arguments the SDK
/// put on the wire.
fn calldata(p : @provider.MockProvider) -> String {
  guard p.last_call() is Some((_, params)) else { return "no call" }
  guard params is [Object(request), ..] else { return "no request object" }
  guard request.get("data") is Some(String(data)) else { return "no data" }
  data
}

///|
/// The account the last transaction was sent from — for these calls, the
/// submitter, who is never the holder.
fn sender(p : @provider.MockProvider) -> String {
  guard p.last_call() is Some((_, params)) else { return "no call" }
  guard params is [Object(request), ..] else { return "no request object" }
  guard request.get("from") is Some(String(from)) else { return "no from" }
  from
}

///|
fn sending() -> @provider.MockProvider {
  @provider.MockProvider::new().on(
    method_name="eth_sendTransaction",
    response=Json::string(
      "0x00000000000000000000000000000000000000000000000000000000000000ff",
    ),
  )
}

///|
/// The relayer pays and the holder's units move: the six members of the
/// authorization go out as the token wants them, the signature behind them.
async test "transfer_with_authorization submits what the holder signed" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let hash = @stablecoin.Stablecoin::new(token()).transfer_with_authorization(
      wallet,
      submitter=relayer(),
      authorization=authorization(),
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      hash.to_string(),
      content="0x00000000000000000000000000000000000000000000000000000000000000ff",
    )
    inspect(
      sender(wallet),
      content="0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
    )
    inspect(
      calldata(wallet),
      content=(
        #|0xe3ee160e000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000dead00000000000000000000000000000000000000000000003635c9adc5dea000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007735940000000000000000000000000000000000000000000000000000000000000000ff000000000000000000000000000000000000000000000000000000000000001c76819cc2546866185f3265c80819b675b99aeaac49b3cf8c800f2605682b33574587464c8c46a3bb86be84c7182414fe4279dede963704f39314119be97acd8d
      ),
    )
  })
}

///|
/// The receive form is the same nine arguments under another selector.
async test "receive_with_authorization differs from transfer only in the selector" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let _ = @stablecoin.Stablecoin::new(token()).receive_with_authorization(
      wallet,
      submitter=payee(),
      authorization=authorization(),
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet)[:10].to_owned(),
      content=(
        #|0xef55bec6
      ),
    )
  })
}

///|
async test "cancel_authorization burns the nonce it was signed against" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let cancellation = @eip3009.CancelAuthorization::new(
      authorizer=holder(),
      nonce=nonce(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let _ = @stablecoin.Stablecoin::new(token()).cancel_authorization(
      wallet,
      submitter=holder(),
      cancellation~,
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet),
      content=(
        #|0x5a049a70000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb9226600000000000000000000000000000000000000000000000000000000000000ff000000000000000000000000000000000000000000000000000000000000001c76819cc2546866185f3265c80819b675b99aeaac49b3cf8c800f2605682b33574587464c8c46a3bb86be84c7182414fe4279dede963704f39314119be97acd8d
      ),
    )
  })
}

///|
async test "permit submits the allowance the owner signed" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let permit = @eip2612.Permit::new(
      owner=holder(),
      spender=payee(),
      value=1000,
      nonce=0,
      deadline=2000000000,
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let _ = @stablecoin.Stablecoin::new(token()).permit(
      wallet,
      submitter=payee(),
      permit~,
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet),
      content=(
        #|0xd505accf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000dead00000000000000000000000000000000000000000000000000000000000003e80000000000000000000000000000000000000000000000000000000077359400000000000000000000000000000000000000000000000000000000000000001c76819cc2546866185f3265c80819b675b99aeaac49b3cf8c800f2605682b33574587464c8c46a3bb86be84c7182414fe4279dede963704f39314119be97acd8d
      ),
    )
  })
}

///|
/// A nonce is spent once, whether it was submitted or cancelled.
async test "authorization_state reads the token's mark" {
  @async.with_task_group(_ => {
    let wallet = answering(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
    )
    inspect(
      @stablecoin.Stablecoin::new(token()).authorization_state(
        wallet,
        authorizer=holder(),
        nonce=nonce(),
      ) catch {
        e => fail("unexpected error: \{e}")
      },
      content="true",
    )
    inspect(
      calldata(wallet),
      content=(
        #|0xe94a0102000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb9226600000000000000000000000000000000000000000000000000000000000000ff
      ),
    )
  })
}

///|
/// A signature the token's `ecrecover` would refuse is refused here, for the
/// price of no transaction.
async test "a signature that is not 65 bytes is refused before anything is sent" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let short = @types.Hex::from_string("0xdeadbeef") catch {
      e => fail("unexpected error: \{e}")
    }
    try
      @stablecoin.Stablecoin::new(token()).transfer_with_authorization(
        wallet,
        submitter=relayer(),
        authorization=authorization(),
        signature=short,
      )
      |> ignore
    catch {
      e =>
        inspect(
          e,
          content=(
            #|Abi(InvalidData("signature must be 65 bytes: 0xdeadbeef"))
          ),
        )
    } noraise {
      _ => fail("a four-byte signature was accepted")
    }
    inspect(wallet.calls().length(), content="0")
  })
}

///|
/// What a token answers a `string` getter with.
fn string_answer(text : String) -> Json {
  Json::string(@abi.encode([String], [String(text)]).to_string()) catch {
    e => abort("bad test answer: \{e}")
  }
}

///|
/// The domain a caller would otherwise have to spell, and the one the token
/// itself confirms.
fn expected_domain() -> @eip712.TypedDataDomain {
  @eip3009.domain(
    name="JPY Coin",
    version="1",
    chain_id=@types.ChainId::mainnet(),
    token=token(),
  ) catch {
    e => abort("bad test domain: \{e}")
  }
}

///|
/// A provider answering `name()`, `version()` and `DOMAIN_SEPARATOR()` in that
/// order, with the separator it is given.
fn token_of(version : @provider.Answer) -> @provider.MockProvider {
  let separator = expected_domain().separator() catch {
    e => abort("bad test separator: \{e}")
  }
  @provider.MockProvider::new()
  .on(method_name="eth_chainId", response=Json::string("0x1"))
  .on_sequence(method_name="eth_call", answers=[
    Answers(string_answer("JPY Coin")),
    version,
    Answers(Json::string(separator.to_string())),
  ])
}

///|
/// The whole domain in one answer: the token is asked what it calls itself and
/// then asked to confirm the result.
async test "domain reads the token's own and checks it against the separator" {
  @async.with_task_group(_ => {
    let wallet = token_of(Answers(string_answer("1")))
    let domain = @stablecoin.Stablecoin::new(token()).domain(wallet) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(domain == expected_domain(), content="true")
  })
}

///|
/// A token without `version()` is answered as `"1"` — a guess, which is why the
/// separator has the last word.
async test "domain falls back to version 1 where there is no version()" {
  @async.with_task_group(_ => {
    let wallet = token_of(Raises(@provider.UnsupportedMethod))
    let domain = @stablecoin.Stablecoin::new(token()).domain(wallet) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(domain == expected_domain(), content="true")
  })
}

///|
/// And a domain the token does not recognize is refused here rather than after
/// a user has signed against it.
async test "domain refuses a separator that is not the token's" {
  @async.with_task_group(_ => {
    let wallet = token_of(Answers(string_answer("2")))
    try @stablecoin.Stablecoin::new(token()).domain(wallet) |> ignore catch {
      e =>
        inspect(
          e,
          content=(
            #|Abi(InvalidData("the contract's DOMAIN_SEPARATOR() is 0x4a6710a6c991ed98dc680e7b543d6c00beb16120340e91044b4f388ecdfecc2c, but this domain hashes to 0xd0719861a1cb37676cf4ea27d6561d7a0a6370027a2f148dc053ccf612fc8132 — its name, version, chain or shape is not what the contract verifies under"))
          ),
        )
    } noraise {
      _ => fail("a domain the token rejects was accepted")
    }
  })
}

///|
/// The same signature spelled the way a typed transaction spells it — `v` of
/// `0` or `1` rather than `27` or `28` — reaches the token as the same nine
/// arguments.
async test "a signature with a v of 0 or 1 is the same signature" {
  @async.with_task_group(_ => {
    let token = @stablecoin.Stablecoin::new(token())
    let wallet = sending()
    let _ = token.transfer_with_authorization(
      wallet,
      submitter=relayer(),
      authorization=authorization(),
      signature=raw_signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let with_offset = sending()
    let _ = token.transfer_with_authorization(
      with_offset,
      submitter=relayer(),
      authorization=authorization(),
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(calldata(wallet) == calldata(with_offset), content="true")
  })
}

///|
/// The ERC-20 face is on the stablecoin itself: the read goes out without the
/// caller changing type first, and comes back as a number.
async test "balance_of reads the token without going through token()" {
  @async.with_task_group(_ => {
    let wallet = answering(
      "0x00000000000000000000000000000000000000000000000000000000000003e8",
    )
    let balance = @stablecoin.Stablecoin::new(token()).balance_of(
      wallet,
      holder(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(balance, content="1000")
  })
}

///|
/// And it is the same call, not a second spelling of it: what a delegated
/// method puts on the wire is what `@erc20.Erc20` puts there. The bytes
/// themselves are pinned in `contract/erc20`, which is where they are decided.
async test "the delegated calls are the ERC-20 ones" {
  @async.with_task_group(_ => {
    let coin = @stablecoin.Stablecoin::new(token())
    let plain = @erc20.Erc20::new(token())
    let answer = "0x0000000000000000000000000000000000000000000000000000000000000006"
    let read = answering(answer)
    let read_plain = answering(answer)
    coin.decimals(read) |> ignore
    plain.decimals(read_plain) |> ignore
    inspect(calldata(read) == calldata(read_plain), content="true")
    let owner = answering(answer)
    let owner_plain = answering(answer)
    coin.balance_of(owner, holder()) |> ignore
    plain.balance_of(owner_plain, holder()) |> ignore
    inspect(calldata(owner) == calldata(owner_plain), content="true")
    let sent = sending()
    let sent_plain = sending()
    coin.transfer(sent, from=holder(), to=payee(), amount=1000N) |> ignore
    plain.transfer(sent_plain, from=holder(), to=payee(), amount=1000N)
    |> ignore
    inspect(calldata(sent) == calldata(sent_plain), content="true")
    // the delegated `transfer` is the one that pays for itself: `from` sends
    inspect(sender(sent), content="0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266")
  })
}

///|
/// A signature a contract answered with: not 65 bytes, not an ECDSA pair, and
/// nothing this SDK can check — the token asks the signer itself.
fn contract_signature() -> @types.Hex {
  @types.Hex::from_string("0xdeadbeef") catch {
    e => abort("bad test signature: \{e}")
  }
}

///|
/// The four V2_2 selectors, spelled out so a change to the argument list shows
/// up here rather than as a revert on chain.
test "the bytes overloads are FiatTokenV2_2's four selectors" {
  inspect(
    @abi.selector(
      "transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)",
    ),
    content=(
      #|0xcf092995
    ),
  )
  inspect(
    @abi.selector(
      "receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)",
    ),
    content=(
      #|0x88b7ab63
    ),
  )
  inspect(
    @abi.selector("cancelAuthorization(address,bytes32,bytes)"),
    content=(
      #|0xb7b72899
    ),
  )
  inspect(
    @abi.selector("permit(address,address,uint256,uint256,bytes)"),
    content=(
      #|0x9fd5a6cf
    ),
  )
}

///|
/// The contract wallet's half: the same six members of the authorization, and
/// the signature after them as `bytes` rather than as `(v, r, s)`.
async test "transfer_with_authorization_1271 sends the signature as bytes" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let _ = @stablecoin.Stablecoin::new(token()).transfer_with_authorization_1271(
      wallet,
      submitter=relayer(),
      authorization=authorization(),
      signature=contract_signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet),
      content=(
        #|0xcf092995000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000dead00000000000000000000000000000000000000000000003635c9adc5dea000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007735940000000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000004deadbeef00000000000000000000000000000000000000000000000000000000
      ),
    )
  })
}

///|
async test "receive_with_authorization_1271 differs only in the selector" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let _ = @stablecoin.Stablecoin::new(token()).receive_with_authorization_1271(
      wallet,
      submitter=payee(),
      authorization=authorization(),
      signature=contract_signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet)[:10].to_owned(),
      content=(
        #|0x88b7ab63
      ),
    )
  })
}

///|
async test "cancel_authorization_1271 sends the signature as bytes" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let cancellation = @eip3009.CancelAuthorization::new(
      authorizer=holder(),
      nonce=nonce(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let _ = @stablecoin.Stablecoin::new(token()).cancel_authorization_1271(
      wallet,
      submitter=holder(),
      cancellation~,
      signature=contract_signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet),
      content=(
        #|0xb7b72899000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb9226600000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004deadbeef00000000000000000000000000000000000000000000000000000000
      ),
    )
  })
}

///|
async test "permit_1271 sends the signature as bytes" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let permit = @eip2612.Permit::new(
      owner=holder(),
      spender=payee(),
      value=1000,
      nonce=0,
      deadline=2000000000,
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let _ = @stablecoin.Stablecoin::new(token()).permit_1271(
      wallet,
      submitter=payee(),
      permit~,
      signature=contract_signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    inspect(
      calldata(wallet),
      content=(
        #|0x9fd5a6cf000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000dead00000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000007735940000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000004deadbeef00000000000000000000000000000000000000000000000000000000
      ),
    )
  })
}

///|
/// An EOA's 65 bytes go through the bytes form too — the token unpacks them
/// itself. What the caller chooses is the selector, never the SDK by length.
async test "the bytes form takes a 65-byte signature as it is" {
  @async.with_task_group(_ => {
    let wallet = sending()
    let _ = @stablecoin.Stablecoin::new(token()).transfer_with_authorization_1271(
      wallet,
      submitter=relayer(),
      authorization=authorization(),
      signature=signature(),
    ) catch {
      e => fail("unexpected error: \{e}")
    }
    let sent = calldata(wallet)
    inspect(
      sent[:10].to_owned(),
      content=(
        #|0xcf092995
      ),
    )
    // the 65 bytes, unchanged and right where the offset points
    inspect(sent.contains(signature().to_string()[2:]), content="true")
  })
}
