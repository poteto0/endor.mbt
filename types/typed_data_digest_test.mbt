///|
/// The full `Mail` example EIP-712 itself is written around (unlike
/// `typed_data_test.mbt`'s trimmed fixture): both `Person`s are present, which
/// is what lets every hash here be checked against the spec's own published
/// values.
fn full_mail_types() -> Map[String, Array[@types.TypedDataField]] raise @types.CodecError {
  {
    "Person": [
      @types.TypedDataField::new("name", "string"),
      @types.TypedDataField::new("wallet", "address"),
    ],
    "Mail": [
      @types.TypedDataField::new("from", "Person"),
      @types.TypedDataField::new("to", "Person"),
      @types.TypedDataField::new("contents", "string"),
    ],
  }
}

///|
fn full_mail_domain() -> @types.TypedDataDomain raise @types.CodecError {
  @types.TypedDataDomain::new(
    name="Ether Mail",
    version="1",
    chain_id=@types.ChainId::mainnet(),
    verifying_contract=@types.Address::from_string(
      "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    ),
  )
}

///|
fn full_mail_message() -> Json {
  {
    "from": {
      "name": "Cow",
      "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
    },
    "to": {
      "name": "Bob",
      "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
    },
    "contents": "Hello, Bob!",
  }
}

///|
fn full_mail() -> @types.TypedData raise @types.CodecError {
  @types.TypedData::new(
    full_mail_domain(),
    primary_type="Mail",
    types=full_mail_types(),
    message=full_mail_message(),
  )
}

///|
/// `encodeType` lists the primary type first and its referenced struct types
/// afterwards, alphabetized — here just `Person`, since `Mail` is already
/// first.
test "encodeType matches the EIP-712 spec's Mail example" {
  inspect(
    full_mail().encode_type("Mail"),
    content="Mail(Person from,Person to,string contents)Person(string name,address wallet)",
  )
}

///|
/// `typeHash` = `keccak256(encodeType(Mail))`, checked against the spec's own
/// published value.
test "typeHash matches the EIP-712 spec's Mail example" {
  inspect(
    full_mail().type_hash("Mail").to_string(),
    content="0xa0cedeb2dc280ba39b857546d74f5549c3a1d7bdc2dd96bf881f76108e23dac2",
  )
}

///|
/// `hashStruct(message)`, checked against the spec's own published value.
test "hashStruct matches the EIP-712 spec's Mail example" {
  inspect(
    full_mail().hash_struct().to_string(),
    content="0xc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e",
  )
}

///|
/// `domainSeparator`, checked against the spec's own published value.
test "domainSeparator matches the EIP-712 spec's Mail example" {
  inspect(
    full_mail().domain_separator().to_string(),
    content="0xf2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f",
  )
}

///|
/// `digest`, checked against the spec's own published value — the hash a
/// wallet actually signs for this document.
test "digest matches the EIP-712 spec's Mail example" {
  inspect(
    full_mail().digest().to_string(),
    content="0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2",
  )
}

///|
/// A type name the document does not define is an ordinary caller mistake —
/// type names are strings, and an EIP-712 document is often assembled at
/// runtime — so `encodeType` / `typeHash` raise rather than panic, with the
/// same wording `encodeData` already uses for an undefined type.
test "encodeType and typeHash raise on an undefined type name" {
  let doc = full_mail()
  try doc.encode_type("NoSuchType") |> ignore catch {
    InvalidJson(m) => inspect(m, content="NoSuchType is not defined")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
  try doc.type_hash("NoSuchType") |> ignore catch {
    InvalidJson(m) => inspect(m, content="NoSuchType is not defined")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// An array field's `encodeData` is the hash of its elements' own encoding,
/// concatenated — checked against an independent computation rather than a
/// published vector, since the spec's own example carries no array.
test "hashStruct of an array field hashes its concatenated elements" {
  let doc = @types.TypedData::new(
    @types.TypedDataDomain::new(name="Endor"),
    primary_type="Only",
    types={ "Only": [@types.TypedDataField::new("it", "uint256[]")] },
    message={ "it": [Json::number(1), Json::number(2), Json::number(3)] },
  )
  inspect(
    doc.type_hash("Only").to_string(),
    content="0x8a89b3ddd62a5bf2e3e6fa014fc543625fca1c49b874976258b00d60d0b3741a",
  )
  inspect(
    doc.hash_struct().to_string(),
    content="0x41956e302cfbe948a346b9ede7b1f99748cd680fc402861db60df4842ec606ba",
  )
}
