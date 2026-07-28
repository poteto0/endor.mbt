///|
/// EIP-712 hashing (#45): the digest a wallet signs over, computed locally.
///
/// `TypedData::new` validates a document but hashes nothing — the wallet
/// computes the digest, so nothing here had a caller until now. What follows
/// is `encodeType` / `typeHash` / `encodeData` / `hashStruct` /
/// `domainSeparator`, built up to the final `digest`, checked against the
/// EIP-712 spec's own `Mail` example.

///|
/// `encodeType(type_name)`: its own member list, followed by every struct
/// type it references (directly or through another struct), alphabetized —
/// `Mail(Person from,Person to,string contents)Person(string name,address wallet)`.
pub fn TypedData::encode_type(self : TypedData, type_name : String) -> String {
  encode_type(self.types, type_name)
}

///|
/// `typeHash(type_name)` = `keccak256(encodeType(type_name))`.
pub fn TypedData::type_hash(self : TypedData, type_name : String) -> Hex {
  Hex::from_bytes(type_hash(self.types, type_name))
}

///|
/// `hashStruct(s)` for the message, at whatever type it declares itself as.
pub fn TypedData::hash_struct(self : TypedData) -> Hex raise CodecError {
  Hex::from_bytes(hash_struct(self.types, self.primary_type, self.message))
}

///|
/// `domainSeparator` — `hashStruct` of the document's `EIP712Domain` value,
/// built over only the fields the domain actually carries.
pub fn TypedData::domain_separator(self : TypedData) -> Hex raise CodecError {
  Hex::from_bytes(domain_separator_bytes(self.domain))
}

///|
/// `digest` = `keccak256(0x19 0x01 ‖ domainSeparator ‖ hashStruct(message))` —
/// the hash a wallet actually signs, and what `isValidSignature` on an
/// EIP-1271 contract wallet takes.
pub fn TypedData::digest(self : TypedData) -> Hex raise CodecError {
  let domain_sep = domain_separator_bytes(self.domain)
  let message_hash = hash_struct(self.types, self.primary_type, self.message)
  let signed = Bytes::makei(66, i => {
    if i == 0 {
      b'\x19'
    } else if i == 1 {
      b'\x01'
    } else if i < 34 {
      domain_sep[i - 2]
    } else {
      message_hash[i - 34]
    }
  })
  Hex::from_bytes(@crypto.keccak256(signed))
}

///|
fn domain_separator_bytes(domain : TypedDataDomain) -> Bytes raise CodecError {
  let types : Map[String, Array[TypedDataField]] = Map([
    (DOMAIN_TYPE, domain.fields()),
  ])
  hash_struct(types, DOMAIN_TYPE, domain.to_json())
}

///|
fn encode_type(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
) -> String {
  let out = StringBuilder::new()
  out.write_string(struct_signature(types, type_name))
  for name in referenced_type_names(types, type_name) {
    out.write_string(struct_signature(types, name))
  }
  out.to_string()
}

///|
/// One type's own `Name(type member,type member,...)` entry — the piece
/// `encodeType` concatenates, once for the primary type and once per struct
/// it references.
fn struct_signature(
  types : Map[String, Array[TypedDataField]],
  name : String,
) -> String {
  let fields = types.get(name).unwrap()
  let members = fields.map(f => "\{f.type_name} \{f.name}").join(",")
  "\{name}(\{members})"
}

///|
/// Every struct type `type_name` refers to, directly or transitively,
/// alphabetized — the order `encodeType` appends them in.
fn referenced_type_names(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  collect_referenced(types, type_name, type_name, seen)
  let names = seen.keys().collect()
  names.sort()
  names
}

///|
fn collect_referenced(
  types : Map[String, Array[TypedDataField]],
  root : String,
  type_name : String,
  seen : Map[String, Unit],
) -> Unit {
  guard types.get(type_name) is Some(fields) else { return }
  for f in fields {
    let base = base_type(f.type_name)
    if base != root && types.get(base) is Some(_) && seen.get(base) is None {
      seen[base] = ()
      collect_referenced(types, root, base, seen)
    }
  }
}

///|
fn type_hash(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
) -> Bytes {
  @crypto.keccak256_string(encode_type(types, type_name))
}

///|
/// `encodeData(s)` = `typeHash ‖` one 32-byte word per field, in declaration
/// order. Every word is exactly 32 bytes — atomic values are packed the way
/// ABI encoding packs them, dynamic values and nested structs are hashed down
/// to one word first — which is what lets this just concatenate them.
fn encode_data(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  value : Json,
) -> Bytes raise CodecError {
  guard value is Object(members) else {
    raise InvalidJson("\{type_name} value must be an object")
  }
  let fields = match types.get(type_name) {
    Some(fs) => fs
    None => raise InvalidJson("\{type_name} is not defined")
  }
  let words = [type_hash(types, type_name)]
  for f in fields {
    let v = match members.get(f.name) {
      Some(v) => v
      None => raise InvalidJson("\{type_name}.\{f.name} is missing")
    }
    words.push(encode_value(types, f.type_name, v))
  }
  concat_words(words)
}

///|
fn hash_struct(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  value : Json,
) -> Bytes raise CodecError {
  @crypto.keccak256(encode_data(types, type_name, value))
}

///|
/// One field's value, as the 32-byte word `encodeData` packs it into: an
/// array is the hash of its encoded elements, a struct is `hashStruct`, and
/// anything else is atomic.
fn encode_value(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  value : Json,
) -> Bytes raise CodecError {
  if array_element(type_name) is Some((element, _)) {
    guard value is Array(items) else {
      raise InvalidJson("expected an array for \{type_name}")
    }
    let words = items.map(item => encode_value(types, element, item))
    @crypto.keccak256(concat_words(words))
  } else if types.get(type_name) is Some(_) {
    hash_struct(types, type_name, value)
  } else {
    encode_atomic(type_name, value)
  }
}

///|
/// An elementary value's word: `bool`/`address`/`uint*`/`int*` are left-padded
/// big-endian (`address` as a 160-bit unsigned integer), `bytes1..32` are
/// right-padded, and `string`/`bytes` are hashed rather than padded, since
/// they are dynamic.
fn encode_atomic(type_name : String, value : Json) -> Bytes raise CodecError {
  match classify_elementary(type_name) {
    Some(String) =>
      match value {
        String(s) => @crypto.keccak256_string(s)
        _ => raise InvalidJson("\{type_name} value must be a string")
      }
    Some(Bytes) =>
      match value {
        String(s) => @crypto.keccak256(Hex::from_string(s).to_bytes())
        _ => raise InvalidJson("\{type_name} value must be a hex string")
      }
    Some(Bool) =>
      match value {
        True => word_of_unsigned(BigInt::from_int(1))
        False => word_of_unsigned(BigInt::from_int(0))
        _ => raise InvalidJson("\{type_name} value must be a boolean")
      }
    Some(Address) =>
      match value {
        String(s) => word_left_pad(Hex::from_string(s).to_bytes())
        _ => raise InvalidJson("\{type_name} value must be an address string")
      }
    Some(FixedBytes(_)) =>
      match value {
        String(s) => word_right_pad(Hex::from_string(s).to_bytes())
        _ => raise InvalidJson("\{type_name} value must be a hex string")
      }
    Some(Uint(_)) =>
      word_of_unsigned(integer_value(value, path=type_name, type_name~))
    Some(Int(_)) =>
      word_of_unsigned(
        to_unsigned256(integer_value(value, path=type_name, type_name~)),
      )
    None => raise InvalidJson("\{type_name} is not an elementary type")
  }
}

///|
/// The two's complement of a signed value in 256 bits: unchanged if it is
/// already non-negative, `n + 2^256` otherwise.
fn to_unsigned256(n : BigInt) -> BigInt {
  if n < BigInt::from_int(0) {
    n + (BigInt::from_int(1) << 256)
  } else {
    n
  }
}

///|
/// `n` as a big-endian 32-byte word. `n` must already be non-negative and
/// below `2^256`, which every caller here has arranged for.
fn word_of_unsigned(n : BigInt) -> Bytes {
  n.to_octets(length=32)
}

///|
/// Right-align `bytes` within one 32-byte word — where `address` and `uint`
/// go once converted to raw bytes.
fn word_left_pad(bytes : Bytes) -> Bytes {
  let pad = 32 - bytes.length()
  Bytes::makei(32, i => if i < pad { b'\x00' } else { bytes[i - pad] })
}

///|
/// Left-align `bytes` within one 32-byte word and zero-fill the rest — where
/// `bytes1`..`bytes32` go.
fn word_right_pad(bytes : Bytes) -> Bytes {
  Bytes::makei(32, i => if i < bytes.length() { bytes[i] } else { b'\x00' })
}

///|
/// Concatenate a run of 32-byte words. Every element `encode_data` and
/// `encode_value` produce is exactly one word, which is what lets
/// concatenation be this simple.
fn concat_words(words : Array[Bytes]) -> Bytes {
  Bytes::makei(words.length() * 32, i => words[i / 32][i % 32])
}
