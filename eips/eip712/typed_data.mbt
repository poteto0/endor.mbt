///|
/// One member of an EIP-712 struct type: the name it is spelled with in the
/// message, and the type it is declared as.
///
/// ```mbt check
/// test "doc: typed data field" {
///   let f = TypedDataField::new("contents", "string")
///   inspect(
///     f.to_json().stringify(),
///     content=(
///       #|{"name":"contents","type":"string"}
///     ),
///   )
/// }
/// ```
pub struct TypedDataField {
  priv name : String
  priv type_name : String
} derive(Eq, Debug)

///|
/// Declare a member. Whether the type resolves — whether a struct name is one
/// the document defines — is `TypedData::new`'s job, since it is the only place
/// that knows the whole registry; here the spelling itself is checked.
pub fn TypedDataField::new(
  name : String,
  type_name : String,
) -> TypedDataField raise @types.CodecError {
  guard !name.is_empty() else {
    raise @types.InvalidJson("typed data field has no name")
  }
  guard !base_type(type_name).is_empty() else {
    raise @types.InvalidJson(
      "typed data field \{name} has no type: \{type_name}",
    )
  }
  TypedDataField::{ name, type_name }
}

///|
/// Encode as the `{ name, type }` object an EIP-712 type definition is a list
/// of.
pub fn TypedDataField::to_json(self : TypedDataField) -> Json {
  { "name": self.name.to_json(), "type": self.type_name.to_json() }
}

///|
/// The domain a signature is bound to (EIP-712 `EIP712Domain`): what stops a
/// signature made for one dapp, one chain or one contract from being replayed
/// against another.
///
/// Every field is optional, and **only the ones present take part** — the
/// domain separator is hashed over exactly the fields the document declares, so
/// adding one later changes every signature. That is also why the
/// `EIP712Domain` type entry is derived from this rather than spelled by the
/// caller: the two cannot then disagree.
///
/// ```mbt check
/// test "doc: typed data domain" {
///   let domain = TypedDataDomain::new(
///     name="Ether Mail",
///     version="1",
///     chain_id=@types.ChainId::mainnet(),
///   )
///   inspect(
///     domain.to_json().stringify(),
///     content=(
///       #|{"name":"Ether Mail","version":"1","chainId":1}
///     ),
///   )
/// }
/// ```
pub struct TypedDataDomain {
  priv name : String?
  priv version : String?
  priv chain_id : @types.ChainId?
  priv verifying_contract : @types.Address?
  priv salt : @types.Hex?
} derive(Eq, Debug)

///|
/// Describe a signing domain. `salt` is the rarely used last resort of the
/// five, and must be 32 bytes.
pub fn TypedDataDomain::new(
  name? : String,
  version? : String,
  chain_id? : @types.ChainId,
  verifying_contract? : @types.Address,
  salt? : @types.Hex,
) -> TypedDataDomain raise @types.CodecError {
  if salt is Some(s) {
    guard s.byte_length() == 32 else {
      raise @types.InvalidLength(
        "typed data domain salt must be 32 bytes: \{s}",
      )
    }
  }
  TypedDataDomain::{ name, version, chain_id, verifying_contract, salt }
}

///|
/// The `EIP712Domain` type entry: the fields that are there, in the order
/// EIP-712 fixed for them. Order is part of the hash, so it is fixed here and
/// not left to the order a caller happened to pass them in.
pub fn TypedDataDomain::fields(self : TypedDataDomain) -> Array[TypedDataField] {
  let fields = []
  if self.name is Some(_) {
    fields.push(TypedDataField::{ name: "name", type_name: "string" })
  }
  if self.version is Some(_) {
    fields.push(TypedDataField::{ name: "version", type_name: "string" })
  }
  if self.chain_id is Some(_) {
    fields.push(TypedDataField::{ name: "chainId", type_name: "uint256" })
  }
  if self.verifying_contract is Some(_) {
    fields.push(TypedDataField::{
      name: "verifyingContract",
      type_name: "address",
    })
  }
  if self.salt is Some(_) {
    fields.push(TypedDataField::{ name: "salt", type_name: "bytes32" })
  }
  fields
}

///|
/// Encode as the `domain` object of the document. `chainId` goes out as a JSON
/// number rather than a hex quantity: this is EIP-712's own encoding, not the
/// JSON-RPC one, and a chain id is far below the range a double stops being
/// exact at.
pub fn TypedDataDomain::to_json(self : TypedDataDomain) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.name is Some(name) {
    fields["name"] = name.to_json()
  }
  if self.version is Some(version) {
    fields["version"] = version.to_json()
  }
  if self.chain_id is Some(chain_id) {
    fields["chainId"] = Json::number(chain_id.to_uint64().to_double())
  }
  if self.verifying_contract is Some(contract) {
    fields["verifyingContract"] = contract.to_json()
  }
  if self.salt is Some(salt) {
    fields["salt"] = salt.to_json()
  }
  Json::object(fields)
}

///|
/// An EIP-712 typed-data document: the struct types, which of them the message
/// is, the domain it is bound to, and the message itself.
///
/// This is what `@provider.sign_typed_data` sends. Building one validates it —
/// `primaryType` has to be defined, every type a field refers to has to be
/// defined or elementary, and the message has to match the type it claims to
/// be, member for member — so a document a wallet would reject is caught here,
/// where the error can say which field went wrong, rather than coming back as
/// an opaque wallet-side failure.
///
/// The message stays `Json` because a value is only meaningful against the type
/// it is declared as, and that declaration lives in `types`: checking the two
/// against each other is what this does, and a second typed value tree would
/// only restate it.
///
/// Sending a document hashes nothing: the wallet computes the digest, so
/// neither the domain separator nor `hashStruct` is needed to sign. They are
/// computed here anyway — `digest.mbt`, #45 — for the callers that need the
/// hash itself rather than a signature over it, EIP-1271 being the first.
///
/// ```mbt check
/// test "doc: typed data" {
///   let mail = TypedData::new(
///     TypedDataDomain::new(name="Ether Mail", chain_id=@types.ChainId::mainnet()),
///     primary_type="Mail",
///     types={
///       "Mail": [
///         TypedDataField::new("from", "address"),
///         TypedDataField::new("contents", "string"),
///       ],
///     },
///     message={
///       "from": "0x52908400098527886e0f7030069857d2e4169ee7",
///       "contents": "Hello, Bob!",
///     },
///   )
///   inspect(mail.primary_type(), content="Mail")
/// }
/// ```
pub struct TypedData {
  priv types : Map[String, Array[TypedDataField]]
  priv primary_type : String
  priv domain : TypedDataDomain
  priv message : Json
} derive(Eq, Debug)

///|
/// Assemble and validate a document.
///
/// `types` holds the caller's own struct types only: `EIP712Domain` is derived
/// from `domain` and declaring it here is an error, since a document carrying
/// two answers for it would sign one and display the other.
pub fn TypedData::new(
  domain : TypedDataDomain,
  primary_type~ : String,
  types~ : Map[String, Array[TypedDataField]],
  message~ : Json,
) -> TypedData raise @types.CodecError {
  guard primary_type != DOMAIN_TYPE else {
    raise @types.InvalidJson(
      "primaryType must be a struct type, not \{DOMAIN_TYPE}",
    )
  }
  for name, fields in types {
    guard name != DOMAIN_TYPE else {
      raise @types.InvalidJson(
        "\{DOMAIN_TYPE} is derived from the domain and must not be declared",
      )
    }
    for f in fields {
      let base = base_type(f.type_name)
      guard is_elementary(base) || types.get(base) is Some(_) else {
        raise @types.InvalidJson(
          "\{name}.\{f.name} has type \{f.type_name}, which is not defined",
        )
      }
    }
  }
  guard types.get(primary_type) is Some(_) else {
    raise @types.InvalidJson("primaryType \{primary_type} is not defined")
  }
  validate_value(types, primary_type, message, path=primary_type)
  TypedData::{ types, primary_type, domain, message }
}

///|
/// Which of the document's types the message is.
pub fn TypedData::primary_type(self : TypedData) -> String {
  self.primary_type
}

///|
/// Encode as the `{ types, primaryType, domain, message }` document
/// `eth_signTypedData_v4` takes. The derived `EIP712Domain` entry comes first,
/// the way every wallet's own examples spell it.
pub fn TypedData::to_json(self : TypedData) -> Json {
  let type_defs : Map[String, Json] = Map([
    (DOMAIN_TYPE, fields_to_json(self.domain.fields())),
  ])
  for name, fields in self.types {
    type_defs[name] = fields_to_json(fields)
  }
  {
    "types": Json::object(type_defs),
    "primaryType": self.primary_type.to_json(),
    "domain": self.domain.to_json(),
    "message": self.message,
  }
}

///|
/// The type entry EIP-712 derives from a domain, and the one name a caller's
/// own types may not use.
const DOMAIN_TYPE : String = "EIP712Domain"

///|
fn fields_to_json(fields : Array[TypedDataField]) -> Json {
  Json::array(fields.map(f => f.to_json()))
}

///|
/// The element type of an array type, and the length a fixed-size suffix
/// carried (`None` for `[]`). `None` when the type is not an array at all.
///
/// Only the outermost suffix is taken off, so `uint256[2][]` reads as an
/// unbounded array of `uint256[2]` and recursion handles the rest.
fn array_element(type_name : String) -> (String, Int?)? {
  guard type_name.has_suffix("]") else { return None }
  let body = type_name[0:type_name.length() - 1].to_owned()
  guard body.rev_find("[") is Some(open) else { return None }
  let inner = body[open + 1:].to_owned()
  let element = body[0:open].to_owned()
  if inner.is_empty() {
    Some((element, None))
  } else {
    match parse_size(inner) {
      Some(n) => Some((element, Some(n)))
      // `uint256[x]` is not an array type at all, and it is not a struct name
      // either — it falls through to the elementary check, which names it
      None => None
    }
  }
}

///|
/// The type an array type is ultimately made of: `Person[2][]` is built from
/// `Person`. This is what a field's type has to resolve to.
fn base_type(type_name : String) -> String {
  match array_element(type_name) {
    Some((element, _)) => base_type(element)
    None => type_name
  }
}

///|
/// Parse a decimal size — an array length, or the bit width or byte count in an
/// elementary type's name. `None` when it is not digits, or is long enough to
/// be a denial of service rather than a size.
fn parse_size(s : String) -> Int? {
  guard s.length() > 0 && s.length() <= 3 else { return None }
  let mut n = 0
  for c in s {
    guard c.is_ascii_digit() else { return None }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Classify `type_name` as one of EIP-712's own atomic types — `address`,
/// `bool`, `string`, `bytes`, `bytes1`…`bytes32`, `uint8`…`uint256` and
/// `int8`…`int256` in steps of 8 — or `None` if it is neither elementary nor
/// (necessarily) a struct name.
///
/// This reuses `@types.AbiType` rather than a type of its own: EIP-712's atomic
/// types are, by design, exactly the ABI's own (EIP-712 hashes an atomic
/// value the way the ABI encodes it), and the two now live in the same
/// package. Only the seven atomic variants are ever returned here —
/// `Array`/`FixedArray`/`Tuple` are the ABI's compound types, which have no
/// place in this classification (an EIP-712 array or struct field is handled
/// by `array_element` / the document's own `types` map instead).
fn classify_elementary(type_name : String) -> @types.AbiType? {
  match type_name {
    "string" => Some(String)
    "bytes" => Some(Bytes)
    "bool" => Some(Bool)
    "address" => Some(@types.Address)
    _ =>
      if elementary_size(type_name, prefix="bytes") is Some(n) {
        if @codec.is_valid_bytes_size(n) {
          Some(FixedBytes(n))
        } else {
          None
        }
      } else if elementary_size(type_name, prefix="uint") is Some(bits) {
        if @codec.is_valid_bits(bits) {
          Some(Uint(bits))
        } else {
          None
        }
      } else if elementary_size(type_name, prefix="int") is Some(bits) {
        if @codec.is_valid_bits(bits) {
          Some(Int(bits))
        } else {
          None
        }
      } else {
        None
      }
  }
}

///|
/// Whether `type_name` is one of EIP-712's own types rather than a struct the
/// document defines.
fn is_elementary(type_name : String) -> Bool {
  classify_elementary(type_name) is Some(_)
}

///|
/// The number in `bytes32` / `uint256` / `int8`, when the name is that prefix
/// followed by digits.
fn elementary_size(type_name : String, prefix~ : String) -> Int? {
  guard type_name.has_prefix(prefix) else { return None }
  parse_size(type_name[prefix.length():].to_owned())
}

///|
/// Check `value` against the type it is declared as, naming the path it was
/// reached by so an error points at the field rather than at the document.
fn validate_value(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  value : Json,
  path~ : String,
) -> Unit raise @types.CodecError {
  if array_element(type_name) is Some((element, length)) {
    guard value is Array(items) else {
      raise @types.InvalidJson("\{path} must be an array (\{type_name})")
    }
    if length is Some(n) {
      guard items.length() == n else {
        raise @types.InvalidLength(
          "\{path} must have \{n} items (\{type_name}), got \{items.length()}",
        )
      }
    }
    for i, item in items {
      validate_value(types, element, item, path="\{path}[\{i}]")
    }
    return
  }
  if types.get(type_name) is Some(fields) {
    guard value is Object(members) else {
      raise @types.InvalidJson("\{path} must be an object (\{type_name})")
    }
    for f in fields {
      guard members.get(f.name) is Some(field_value) else {
        raise @types.InvalidJson(
          "\{path} has no \{f.name}, which \{type_name} declares",
        )
      }
      validate_value(types, f.type_name, field_value, path="\{path}.\{f.name}")
    }
    // a member no type declares is not part of what gets signed, so carrying
    // one means the caller believes something the signature will not say
    for name, _ in members {
      guard declares(fields, name) else {
        raise @types.InvalidJson(
          "\{path} has \{name}, which \{type_name} does not declare",
        )
      }
    }
    return
  }
  validate_elementary(type_name, value, path~)
}

///|
fn declares(fields : Array[TypedDataField], name : String) -> Bool {
  for f in fields {
    if f.name == name {
      return true
    }
  }
  false
}

///|
/// Check a value against an elementary type. An unknown type name reaches here
/// too — `TypedData::new` has already established it is neither a struct nor
/// elementary — and is reported as the unknown type it is.
fn validate_elementary(
  type_name : String,
  value : Json,
  path~ : String,
) -> Unit raise @types.CodecError {
  match classify_elementary(type_name) {
    Some(String) => {
      guard value is String(_) else {
        raise @types.InvalidJson("\{path} must be a string")
      }
    }
    Some(Bool) => {
      guard value is (True | False) else {
        raise @types.InvalidJson("\{path} must be a boolean")
      }
    }
    Some(@types.Address) => {
      guard value is String(s) else {
        raise @types.InvalidJson("\{path} must be an address string")
      }
      ignore(@types.Address::from_string(s))
    }
    Some(Bytes) => {
      guard value is String(s) else {
        raise @types.InvalidJson("\{path} must be a hex string")
      }
      ignore(@types.Hex::from_string(s))
    }
    Some(FixedBytes(n)) => {
      guard value is String(s) else {
        raise @types.InvalidJson("\{path} must be a hex string (\{type_name})")
      }
      let hex = @types.Hex::from_string(s)
      guard hex.byte_length() == n else {
        raise @types.InvalidLength(
          "\{path} must be \{n} bytes (\{type_name}): \{s}",
        )
      }
    }
    Some(Uint(bits)) =>
      validate_integer(value, bits, signed=false, path~, type_name~)
    Some(Int(bits)) =>
      validate_integer(value, bits, signed=true, path~, type_name~)
    // `classify_elementary` never returns `@types.AbiType`'s compound variants —
    // only `array_element` and the document's `types` map produce arrays and
    // structs here — but the match still has to cover them, and raising is
    // what the rest of this file does with a type name it cannot use.
    Some(Array(_) | FixedArray(_, _) | Tuple(_)) | None =>
      raise @types.InvalidJson("\{path} has unknown type \{type_name}")
  }
}

///|
/// Read an integer value off the wire: a JSON number, or (past 2^53, where a
/// double stops holding every value exactly) a decimal or `0x`-prefixed
/// string.
fn integer_value(
  value : Json,
  path~ : String,
  type_name~ : String,
) -> BigInt raise @types.CodecError {
  match value {
    Number(d, ..) => {
      let i = d.to_int64()
      guard i.to_double() == d else {
        raise @types.InvalidJson(
          "\{path} must be a whole number a double still holds exactly (\{type_name}); pass it as a decimal string",
        )
      }
      BigInt::from_int64(i)
    }
    String(s) => parse_integer_string(s, path~, type_name~)
    _ =>
      raise @types.InvalidJson(
        "\{path} must be a number or a numeric string (\{type_name})",
      )
  }
}

///|
/// Check an integer value fits the width it is declared at. A `uint256` does
/// not fit a JSON number, so one that has already lost precision is refused
/// rather than signed: past 2^53 the document has to carry the value as a
/// string, which is what wallets' own examples do.
fn validate_integer(
  value : Json,
  bits : Int,
  signed~ : Bool,
  path~ : String,
  type_name~ : String,
) -> Unit raise @types.CodecError {
  let n = integer_value(value, path~, type_name~)
  let fits = if signed {
    @codec.fits_int(n, bits~)
  } else {
    @codec.fits_uint(n, bits~)
  }
  guard fits else {
    raise @types.InvalidLength("\{path} does not fit \{type_name}: \{n}")
  }
}

///|
/// Parse the decimal (or `0x`-prefixed hex) form an integer is carried as when
/// it is too wide for a JSON number.
fn parse_integer_string(
  s : String,
  path~ : String,
  type_name~ : String,
) -> BigInt raise @types.CodecError {
  if s.has_prefix("0x") || s.has_prefix("-0x") {
    let negative = s.has_prefix("-")
    let hex = if negative { s[1:].to_owned() } else { s }
    guard @codec.hex_body(hex) is Some(body) else {
      raise @types.InvalidHex(
        "\{path} is not a hex quantity (\{type_name}): \{s}",
      )
    }
    guard body.length() > 0 else {
      raise @types.InvalidHex(
        "\{path} is an empty quantity (\{type_name}): \{s}",
      )
    }
    let magnitude = BigInt::from_string(body, radix=16)
    return if negative { -magnitude } else { magnitude }
  }
  let negative = s.has_prefix("-")
  let digits = if negative { s[1:].to_owned() } else { s }
  guard digits.length() > 0 else {
    raise @types.InvalidJson("\{path} is not a number (\{type_name}): \{s}")
  }
  for c in digits {
    guard c.is_ascii_digit() else {
      raise @types.InvalidJson("\{path} is not a number (\{type_name}): \{s}")
    }
  }
  let magnitude = BigInt::from_string(digits)
  if negative {
    -magnitude
  } else {
    magnitude
  }
}
