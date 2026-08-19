///|
/// Read back the `{ types, primaryType, domain, message }` document
/// `eth_signTypedData_v4` takes — `to_json`'s inverse, for code that *receives*
/// a document rather than building one.
///
/// It ends in `TypedData::new`, so parsing a document validates it. Three
/// things the wire spells that the struct does not: `EIP712Domain` in `types`,
/// accepted and dropped once it agrees with the domain it is derived from; a
/// member nothing declares, refused; and `chainId` as a string.
///
/// ```mbt check
/// test "doc: typed data from json" {
///   let mail = TypedData::from_json({
///     "types": { "Mail": [{ "name": "contents", "type": "string" }] },
///     "primaryType": "Mail",
///     "domain": { "name": "Ether Mail", "chainId": 1 },
///     "message": { "contents": "Hello, Bob!" },
///   })
///   inspect(mail.primary_type(), content="Mail")
/// }
/// ```
pub fn TypedData::from_json(j : Json) -> TypedData raise @types.CodecError {
  let what = "typed data"
  let doc = json_object(j, what~)
  only_members(doc, ["types", "primaryType", "domain", "message"], what~)
  let domain = domain_from_json(required_member(doc, "domain", what~))
  let types = types_from_json(required_member(doc, "types", what~))
  // the entry the document may carry and the one the domain derives are the
  // same type: it is dropped, but only once the two agree, since the field
  // order is part of the hash and a document holding two answers would sign
  // one of them and display the other
  if types.get(DOMAIN_TYPE) is Some(declared) {
    guard declared == domain.fields() else {
      raise @types.InvalidValue(
        "\{DOMAIN_TYPE} does not match the domain it is derived from",
      )
    }
    types.remove(DOMAIN_TYPE)
  }
  let primary_type = string_member(doc, "primaryType", what~)
  let message = required_member(doc, "message", what~)
  TypedData::new(domain, primary_type~, types~, message~)
}

///|
/// Decode the `domain` object. Every field is optional and only the ones
/// present take part, so a missing field and a `null` one are the same thing
/// here — both mean the domain separator is not hashed over it.
fn domain_from_json(j : Json) -> TypedDataDomain raise @types.CodecError {
  let members = json_object(j, what="typed data domain")
  only_members(
    members,
    ["name", "version", "chainId", "verifyingContract", "salt"],
    what="typed data domain",
  )
  TypedDataDomain::new(
    name?=optional_member(members, "name", v => {
      json_string(v, what="typed data domain name")
    }),
    version?=optional_member(members, "version", v => {
      json_string(v, what="typed data domain version")
    }),
    chain_id?=optional_member(members, "chainId", chain_id_from_json),
    verifying_contract?=optional_member(
      members,
      "verifyingContract",
      @types.Address::from_json,
    ),
    salt?=optional_member(members, "salt", @types.Hex::from_json),
  )
}

///|
/// Decode the `types` object, `EIP712Domain` included: what to do with that
/// entry is `from_json`'s, since only it holds the domain to compare against.
fn types_from_json(
  j : Json,
) -> Map[String, Array[TypedDataField]] raise @types.CodecError {
  let types : Map[String, Array[TypedDataField]] = Map([])
  for name, entry in json_object(j, what="typed data types") {
    let what = "type \{name}"
    let fields = []
    for f in json_array(entry, what~) {
      fields.push(field_from_json(f, what="\{what} field"))
    }
    types[name] = fields
  }
  types
}

///|
/// Decode one `{ name, type }` member of a type definition.
fn field_from_json(
  j : Json,
  what~ : String,
) -> TypedDataField raise @types.CodecError {
  let members = json_object(j, what~)
  only_members(members, ["name", "type"], what~)
  TypedDataField::new(
    string_member(members, "name", what~),
    string_member(members, "type", what~),
  )
}

///|
/// Decode `domain.chainId`, which is a `uint256` in the type entry but a
/// `UInt64` in `ChainId`: a value past that is a well-formed document naming a
/// chain this type cannot hold.
fn chain_id_from_json(j : Json) -> @types.ChainId raise @types.CodecError {
  let n = integer_value(
    j,
    path="typed data domain chainId",
    type_name="uint256",
  )
  guard @codec.fits_uint(n, bits=64) else {
    raise @types.InvalidValue(
      "typed data domain chainId does not fit uint64: \{n}",
    )
  }
  @types.ChainId::new(n.to_uint64())
}

///|
fn json_object(
  j : Json,
  what~ : String,
) -> Map[String, Json] raise @types.CodecError {
  guard j is Object(members) else {
    raise @types.InvalidJson("\{what} must be an object")
  }
  members
}

///|
fn json_array(j : Json, what~ : String) -> Array[Json] raise @types.CodecError {
  guard j is Array(items) else {
    raise @types.InvalidJson("\{what} must be an array")
  }
  items
}

///|
/// A member that has to be there and has to be a string: `primaryType`, and
/// each half of a `{ name, type }` field.
fn string_member(
  members : Map[String, Json],
  name : String,
  what~ : String,
) -> String raise @types.CodecError {
  json_string(required_member(members, name, what~), what="\{what} \{name}")
}

///|
fn json_string(j : Json, what~ : String) -> String raise @types.CodecError {
  guard j is String(s) else {
    raise @types.InvalidJson("\{what} must be a string")
  }
  s
}

///|
/// A member the shape cannot do without. `null` counts as absent, the way it
/// does everywhere else on this wire.
fn required_member(
  members : Map[String, Json],
  name : String,
  what~ : String,
) -> Json raise @types.CodecError {
  guard members.get(name) is Some(v) && !(v is Null) else {
    raise @types.InvalidJson("\{what} has no \{name}")
  }
  v
}

///|
/// A member that may legitimately be missing, decoded if it is there.
fn[T] optional_member(
  members : Map[String, Json],
  name : String,
  decode : (Json) -> T raise @types.CodecError,
) -> T? raise @types.CodecError {
  match members.get(name) {
    None | Some(Null) => None
    Some(v) => Some(decode(v))
  }
}

///|
/// Refuse a member the shape does not declare. Dropping one silently is how a
/// misspelled `chainId` turns into a document that signs something else.
fn only_members(
  members : Map[String, Json],
  declared : Array[String],
  what~ : String,
) -> Unit raise @types.CodecError {
  for name, _ in members {
    guard declared.contains(name) else {
      raise @types.InvalidJson("\{what} has \{name}, which it does not declare")
    }
  }
}
