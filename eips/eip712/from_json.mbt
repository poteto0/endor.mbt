///|
/// Read back the `{ types, primaryType, domain, message }` document
/// `eth_signTypedData_v4` takes — `to_json`'s inverse, and the way in for
/// anything that *receives* a document rather than building one: a payload a
/// wallet is asking about, or an adapter whose own seam is `Json` so that it
/// depends on this package in one place.
///
/// It ends in `TypedData::new`, so what it accepts is what that accepts: the
/// document is validated, not merely parsed.
///
/// Three things the wire spells that the struct does not:
///
/// - **`EIP712Domain` in `types`.** Some producers declare it, some leave it to
///   be derived. It is accepted and dropped — but only when it says exactly
///   what `domain` derives, same fields in the same order, since that order is
///   part of the hash and a document holding two answers would sign one of them
///   and display the other.
/// - **A member nothing declares.** Refused, in the document and in `domain`
///   alike: `chainID` for `chainId` parses perfectly well, drops the field, and
///   changes every signature. The message is already this strict in
///   `TypedData::new`.
/// - **`chainId` as a string.** EIP-712 spells it as a number and `to_json`
///   emits one, but wallets pass `"1"` and `"0x1"` around too, so all three
///   read.
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
  let doc = json_object(j, what="typed data")
  only_members(
    doc,
    ["types", "primaryType", "domain", "message"],
    what="typed data",
  )
  let domain = domain_from_json(
    required_member(doc, "domain", what="typed data"),
  )
  let types = types_from_json(
    required_member(doc, "types", what="typed data"),
    domain,
  )
  let primary_type = json_string(
    required_member(doc, "primaryType", what="typed data"),
    what="typed data primaryType",
  )
  let message = required_member(doc, "message", what="typed data")
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
/// Decode the `types` object, dropping the derived `EIP712Domain` entry once it
/// has been checked against the domain it must agree with.
fn types_from_json(
  j : Json,
  domain : TypedDataDomain,
) -> Map[String, Array[TypedDataField]] raise @types.CodecError {
  let types : Map[String, Array[TypedDataField]] = Map([])
  for name, entry in json_object(j, what="typed data types") {
    let fields = []
    for f in json_array(entry, what="type \{name}") {
      fields.push(field_from_json(f, type_name=name))
    }
    if name == DOMAIN_TYPE {
      guard fields == domain.fields() else {
        raise @types.InvalidValue(
          "\{DOMAIN_TYPE} does not match the domain it is derived from",
        )
      }
      continue
    }
    types[name] = fields
  }
  types
}

///|
/// Decode one `{ name, type }` member of a type definition.
fn field_from_json(
  j : Json,
  type_name~ : String,
) -> TypedDataField raise @types.CodecError {
  let what = "\{type_name} field"
  let members = json_object(j, what~)
  only_members(members, ["name", "type"], what~)
  TypedDataField::new(
    json_string(required_member(members, "name", what~), what="\{what} name"),
    json_string(required_member(members, "type", what~), what="\{what} type"),
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
    raise @types.InvalidValue("typed data domain chainId does not fit: \{n}")
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
