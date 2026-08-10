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
/// Every way a document can be refused, and what the caller is told. The point
/// of each is that the wallet never sees the document — a member nothing
/// declares would not be signed, and a `chainId` misspelled `chainID` would be
/// dropped and change every signature made against it.
test "error documents" {
  let cases : Array[(String, Json)] = [
    ("typed data must be an object", Json::array([])),
    (
      "typed data has signature, which it does not declare",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": "Mail",
        "domain": {},
        "message": { "contents": "Hello" },
        "signature": "0x00",
      },
    ),
    (
      "typed data has no message",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": "Mail",
        "domain": {},
      },
    ),
    (
      "typed data primaryType must be a string",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": Json::number(1),
        "domain": {},
        "message": { "contents": "Hello" },
      },
    ),
    (
      "typed data domain has chainID, which it does not declare",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": "Mail",
        "domain": { "chainID": 1 },
        "message": { "contents": "Hello" },
      },
    ),
    (
      "typed data domain chainId does not fit uint64: 4722366482869645213696",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": "Mail",
        "domain": { "chainId": "0x1000000000000000000" },
        "message": { "contents": "Hello" },
      },
    ),
    (
      "type Mail must be an array",
      {
        "types": { "Mail": { "contents": "string" } },
        "primaryType": "Mail",
        "domain": {},
        "message": { "contents": "Hello" },
      },
    ),
    (
      "type Mail field has indexed, which it does not declare",
      {
        "types": {
          "Mail": [{ "name": "contents", "type": "string", "indexed": false }],
        },
        "primaryType": "Mail",
        "domain": {},
        "message": { "contents": "Hello" },
      },
    ),
    // the order of the derived entry is part of the hash, so a declared
    // `EIP712Domain` that disagrees is refused rather than silently replaced
    (
      "EIP712Domain does not match the domain it is derived from",
      {
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
      },
    ),
    // `from_json` ends in `TypedData::new`, so a document that parses but does
    // not hold together fails the same way one built by hand does
    (
      "Mail.contents must be a string",
      {
        "types": { "Mail": [{ "name": "contents", "type": "string" }] },
        "primaryType": "Mail",
        "domain": {},
        "message": { "contents": 1 },
      },
    ),
  ]
  for c in cases {
    try @eip712.TypedData::from_json(c.1) |> ignore catch {
      @types.InvalidJson(m)
      | @types.InvalidValue(m)
      | @types.InvalidLength(m)
      | @types.InvalidHex(m) => assert_eq(m, c.0)
      e => fail("expected a codec error, but not \{e}")
    } noraise {
      _ => fail("expected \{c.0}, but success")
    }
  }
}
