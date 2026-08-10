///|
/// The document a wallet is handed and the document that built it are the same
/// value: `from_json` is `to_json`'s inverse, derived `EIP712Domain` entry and
/// all.
test "typed data round trips through json" {
  let document = mail().to_json()
  let parsed = @eip712.TypedData::from_json(document)
  assert_eq(parsed, mail())
  assert_eq(parsed.to_json(), document)
}

///|
/// Producers disagree about whether `EIP712Domain` belongs in `types`, so both
/// spellings read — the derived entry is dropped once it has been checked.
test "typed data without the domain type entry" {
  let parsed = @eip712.TypedData::from_json({
    "types": { "Mail": [{ "name": "contents", "type": "string" }] },
    "primaryType": "Mail",
    "domain": { "name": "Ether Mail", "chainId": 1 },
    "message": { "contents": "Hello, Bob!" },
  })
  inspect(
    parsed.to_json().stringify(),
    content=(
      #|{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"chainId","type":"uint256"}],"Mail":[{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"name":"Ether Mail","chainId":1},"message":{"contents":"Hello, Bob!"}}
    ),
  )
}

///|
/// A chain id is a number in EIP-712's own encoding, but the decimal and hex
/// strings wallets pass around mean the same chain.
test "chain id spellings" {
  for spelling in [Json::number(1), "1", "0x1"] {
    let parsed = @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": { "chainId": spelling },
      "message": { "contents": "Hello" },
    })
    inspect(
      parsed.to_json().stringify(),
      content=(
        #|{"types":{"EIP712Domain":[{"name":"chainId","type":"uint256"}],"Mail":[{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"chainId":1},"message":{"contents":"Hello"}}
      ),
    )
  }
}

///|
/// The order of the derived entry is part of the hash, so a declared
/// `EIP712Domain` that disagrees with the domain is refused rather than
/// silently replaced by one of the two.
test "error domain type entry that disagrees with the domain" {
  try
    @eip712.TypedData::from_json({
      "types": {
        "EIP712Domain": [
          { "name": "chainId", "type": "uint256" },
          { "name": "name", "type": "string" },
        ],
        "Mail": [{ "name": "contents", "type": "string" }],
      },
      "primaryType": "Mail",
      "domain": { "name": "Ether Mail", "chainId": 1 },
      "message": { "contents": "Hello" },
    })
    |> ignore
  catch {
    @types.InvalidValue(m) =>
      inspect(
        m,
        content="EIP712Domain does not match the domain it is derived from",
      )
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A misspelled domain field would parse, drop the field, and change every
/// signature made against the document.
test "error domain member nothing declares" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": { "chainID": 1 },
      "message": { "contents": "Hello" },
    })
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(
        m,
        content="typed data domain has chainID, which it does not declare",
      )
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error document member nothing declares" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": {},
      "message": { "contents": "Hello" },
      "signature": "0x00",
    })
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="typed data has signature, which it does not declare")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error document that is not an object" {
  try @eip712.TypedData::from_json(Json::array([])) |> ignore catch {
    @types.InvalidJson(m) => inspect(m, content="typed data must be an object")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error document with no message" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": {},
    })
    |> ignore
  catch {
    @types.InvalidJson(m) => inspect(m, content="typed data has no message")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error type definition that is not a list of fields" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": { "contents": "string" } },
      "primaryType": "Mail",
      "domain": {},
      "message": { "contents": "Hello" },
    })
    |> ignore
  catch {
    @types.InvalidJson(m) => inspect(m, content="type Mail must be an array")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error field member nothing declares" {
  try
    @eip712.TypedData::from_json({
      "types": {
        "Mail": [{ "name": "contents", "type": "string", "indexed": false }],
      },
      "primaryType": "Mail",
      "domain": {},
      "message": { "contents": "Hello" },
    })
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="Mail field has indexed, which it does not declare")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A chain id wider than the type that holds it is a well-formed document
/// naming a chain this SDK cannot address.
test "error chain id that does not fit" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": { "chainId": "0x1000000000000000000" },
      "message": { "contents": "Hello" },
    })
    |> ignore
  catch {
    @types.InvalidValue(m) =>
      inspect(
        m,
        content="typed data domain chainId does not fit: 4722366482869645213696",
      )
    e => fail("expected an invalid value, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// `from_json` ends in `TypedData::new`, so a document that parses but does not
/// hold together fails the same way one built by hand does.
test "error message that does not match its type" {
  try
    @eip712.TypedData::from_json({
      "types": { "Mail": [{ "name": "contents", "type": "string" }] },
      "primaryType": "Mail",
      "domain": {},
      "message": { "contents": 1 },
    })
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="Mail.contents must be a string")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
