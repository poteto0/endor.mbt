///|
/// The `Mail` example EIP-712 itself is written around, trimmed to one `Person`
/// so the nesting is still exercised without the document taking over the file.
fn mail_types() -> Map[String, Array[@eip712.TypedDataField]] raise @types.CodecError {
  {
    "Person": [
      @eip712.TypedDataField::new("name", "string"),
      @eip712.TypedDataField::new("wallet", "address"),
    ],
    "Mail": [
      @eip712.TypedDataField::new("from", "Person"),
      @eip712.TypedDataField::new("contents", "string"),
    ],
  }
}

///|
fn mail_message() -> Json {
  {
    "from": {
      "name": "Cow",
      "wallet": "0x52908400098527886e0f7030069857d2e4169ee7",
    },
    "contents": "Hello, Bob!",
  }
}

///|
fn mail_domain() -> @eip712.TypedDataDomain raise @types.CodecError {
  @eip712.TypedDataDomain::new(
    name="Ether Mail",
    version="1",
    chain_id=@types.ChainId::mainnet(),
    verifying_contract=@types.Address::from_string(
      "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    ),
  )
}

///|
fn mail() -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    mail_domain(),
    primary_type="Mail",
    types=mail_types(),
    message=mail_message(),
  )
}

///|
/// The whole document, as the wallet receives it. `EIP712Domain` is first and
/// derived — the caller never spelled it — and the caller's own types follow.
test "can build a typed data document" {
  inspect(
    mail().to_json().stringify(),
    content=(
      #|{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Person":[{"name":"name","type":"string"},{"name":"wallet","type":"address"}],"Mail":[{"name":"from","type":"Person"},{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"name":"Ether Mail","version":"1","chainId":1,"verifyingContract":"0xcccccccccccccccccccccccccccccccccccccccc"},"message":{"from":{"name":"Cow","wallet":"0x52908400098527886e0f7030069857d2e4169ee7"},"contents":"Hello, Bob!"}}
    ),
  )
  inspect(mail().primary_type(), content="Mail")
}

///|
/// Only the fields that are there take part, and they are listed in EIP-712's
/// own order rather than the order they were passed in.
test "domain declares exactly the fields it carries" {
  let domain = @eip712.TypedDataDomain::new(
    salt=@types.Hex::from_string("0x" + "11".repeat(32)),
    name="Endor",
  )
  inspect(
    Json::array(domain.fields().map(f => f.to_json())).stringify(),
    content=(
      #|[{"name":"name","type":"string"},{"name":"salt","type":"bytes32"}]
    ),
  )
  inspect(
    domain.to_json().stringify(),
    content=(
      #|{"name":"Endor","salt":"0x1111111111111111111111111111111111111111111111111111111111111111"}
    ),
  )
}

///|
/// A domain with nothing in it is legal — it binds the signature to nothing,
/// which is a choice the caller is allowed to make.
test "an empty domain declares no fields" {
  let domain = @eip712.TypedDataDomain::new()
  inspect(domain.fields().length(), content="0")
  inspect(domain.to_json().stringify(), content="{}")
}

///|
test "error salt that is not 32 bytes" {
  try
    @eip712.TypedDataDomain::new(salt=@types.Hex::from_string("0xabcd"))
  catch {
    @types.InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// `EIP712Domain` is derived, so a document that also declares it would carry
/// two answers for the same type — one signed, one shown.
test "error declaring EIP712Domain" {
  try
    @eip712.TypedData::new(
      mail_domain(),
      primary_type="Mail",
      types={
        "EIP712Domain": [@eip712.TypedDataField::new("name", "string")],
        "Mail": [@eip712.TypedDataField::new("contents", "string")],
      },
      message={ "contents": "Hello" },
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(
        m,
        content="EIP712Domain is derived from the domain and must not be declared",
      )
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "error primary type that is not defined" {
  try
    @eip712.TypedData::new(
      mail_domain(),
      primary_type="Letter",
      types=mail_types(),
      message=mail_message(),
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="primaryType Letter is not defined")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A field whose type is neither elementary nor a struct the document defines
/// is caught before the wallet ever sees it.
test "error field type that is not defined" {
  try
    @eip712.TypedData::new(
      mail_domain(),
      primary_type="Mail",
      types={ "Mail": [@eip712.TypedDataField::new("from", "Persona")] },
      message={ "from": Json::empty_object() },
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="Mail.from has type Persona, which is not defined")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The error names the path it was reached by, so a nested document says which
/// field is wrong rather than that the document is.
test "error message missing a declared field" {
  try
    @eip712.TypedData::new(
      mail_domain(),
      primary_type="Mail",
      types=mail_types(),
      message={ "from": { "name": "Cow" }, "contents": "Hello, Bob!" },
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="Mail.from has no wallet, which Person declares")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// A member no type declares is not part of what gets signed, so believing it
/// is signed is exactly the mistake worth refusing.
test "error message carrying an undeclared field" {
  try
    @eip712.TypedData::new(
      mail_domain(),
      primary_type="Mail",
      types=mail_types(),
      message={
        "from": {
          "name": "Cow",
          "wallet": "0x52908400098527886e0f7030069857d2e4169ee7",
        },
        "contents": "Hello, Bob!",
        "urgent": true,
      },
    )
    |> ignore
  catch {
    @types.InvalidJson(m) =>
      inspect(m, content="Mail has urgent, which Mail does not declare")
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Build a one-field document, so a value can be checked against a type
/// without the rest of a document getting in the way.
fn one_field(
  type_name : String,
  value : Json,
) -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    @eip712.TypedDataDomain::new(name="Endor"),
    primary_type="Only",
    types={ "Only": [@eip712.TypedDataField::new("it", type_name)] },
    message={ "it": value },
  )
}

///|
/// The elementary types a value is accepted for.
test "can validate elementary values" {
  ignore(one_field("string", "hello"))
  ignore(one_field("bool", true))
  ignore(one_field("address", "0x52908400098527886e0f7030069857d2e4169ee7"))
  ignore(one_field("bytes", "0xdeadbeef"))
  ignore(one_field("bytes32", Json::string("0x" + "ab".repeat(32))))
  ignore(one_field("uint8", Json::number(255)))
  ignore(one_field("int8", Json::number(-128)))
  // a uint256 does not fit a double, so the wire form for a big one is a string
  ignore(
    one_field(
      "uint256", "115792089237316195423570985008687907853269984665640564039457584007913129639935",
    ),
  )
  ignore(one_field("uint256", "0xff"))
  ignore(one_field("uint256[]", Json::array([Json::number(1), "2"])))
  ignore(one_field("uint256[2]", Json::array([Json::number(1), "2"])))
}

///|
/// Every way a value can fail its declared type. The point of each is that the
/// wallet never sees the document.
test "error values that do not match their type" {
  let cases : Array[(String, Json)] = [
    ("string", Json::number(1)),
    ("bool", "true"),
    ("address", "0x1234"),
    ("address", Json::number(1)),
    ("bytes", "not hex"),
    ("bytes32", "0xabcd"),
    ("uint8", Json::number(256)),
    ("uint8", Json::number(-1)),
    ("int8", Json::number(128)),
    ("uint256", "-1"),
    ("uint256", "twelve"),
    ("uint256", Json::number(1.5)),
    // 2^256, one past what a uint256 holds
    (
      "uint256", "115792089237316195423570985008687907853269984665640564039457584007913129639936",
    ),
    ("uint256[2]", Json::array([Json::number(1)])),
    ("uint256[]", Json::number(1)),
    ("Person", Json::number(1)),
  ]
  for c in cases {
    try one_field(c.0, c.1) |> ignore catch {
      @types.InvalidJson(_) | @types.InvalidLength(_) | @types.InvalidHex(_) =>
        ()
      e => fail("expected a codec error for \{c.0}, but not \{e}")
    } noraise {
      _ => fail("expected \{c.0} to reject its value")
    }
  }
}

///|
/// A number past 2^53 has already lost precision by the time it is a `Json`, so
/// signing it would sign a value the caller did not write.
test "error uint256 as a number that lost precision" {
  try one_field("uint256", Json::number(1.0e30)) |> ignore catch {
    @types.InvalidJson(m) => assert_true(m.contains("decimal string"))
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}
