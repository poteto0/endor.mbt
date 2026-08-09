///|
/// EIP-712 hashing: the digest a wallet signs over, computed locally.
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
/// A type name the document does not define raises `InvalidJson`.
pub fn TypedData::encode_type(
  self : TypedData,
  type_name : String,
) -> String raise @types.CodecError {
  encode_type(self.types, type_name)
}

///|
/// `typeHash(type_name)` = `keccak256(encodeType(type_name))`. A type name the
/// document does not define raises `InvalidJson`.
pub fn TypedData::type_hash(
  self : TypedData,
  type_name : String,
) -> @types.Hex raise @types.CodecError {
  @types.Hex::from_bytes(type_hash(self.types, type_name))
}

///|
/// `hashStruct(s)` for the message, at whatever type it declares itself as.
pub fn TypedData::hash_struct(
  self : TypedData,
) -> @types.Hex raise @types.CodecError {
  let cache : Map[String, Bytes] = Map([])
  @types.Hex::from_bytes(
    @keccak.keccak256(
      encode_data(self.types, self.primary_type, self.message, cache~),
    ),
  )
}

///|
/// `domainSeparator` — `hashStruct` of the document's `EIP712Domain` value,
/// built over only the fields the domain actually carries.
pub fn TypedData::domain_separator(
  self : TypedData,
) -> @types.Hex raise @types.CodecError {
  self.domain.separator()
}

///|
/// The same `domainSeparator`, from a domain that is not yet part of a
/// document.
///
/// It depends on nothing but the domain, and a contract that publishes its own
/// — `DOMAIN_SEPARATOR()`, which every EIP-2612 token has — can therefore be
/// checked against a domain before any message is built.
pub fn TypedDataDomain::separator(
  self : TypedDataDomain,
) -> @types.Hex raise @types.CodecError {
  @types.Hex::from_bytes(domain_separator_bytes(self))
}

///|
/// Refuse a domain the verifying contract would not accept.
///
/// A contract that verifies EIP-712 signatures usually publishes the separator
/// it verifies them under — `DOMAIN_SEPARATOR()`, which every EIP-2612 token
/// has, and which `@erc20.Erc20::domain_separator` reads. Comparing it against
/// the domain built here catches, at the moment the caller builds it and for
/// free, the whole family of mistakes that are otherwise invisible until the
/// chain rejects the transaction: the wrong `version`, a `name` that is not the
/// contract's byte for byte, the wrong chain, a contract that binds a `salt`
/// instead.
///
/// It says nothing about the *message*. A contract whose domain is ordinary and
/// whose document is its own — DAI's permit, say — passes this check and still
/// rejects the signature; what tells those apart is `type_hash`.
pub fn TypedDataDomain::check_separator(
  self : TypedDataDomain,
  on_chain~ : @types.Hex,
) -> Unit raise @types.CodecError {
  let ours = self.separator()
  guard ours == on_chain else {
    raise @types.InvalidJson(
      "the contract's DOMAIN_SEPARATOR() is \{on_chain}, but this domain hashes to \{ours} — its name, version, chain or shape is not what the contract verifies under",
    )
  }
}

///|
/// `digest` = `keccak256(0x19 0x01 ‖ domainSeparator ‖ hashStruct(message))` —
/// the hash a wallet actually signs, and what `isValidSignature` on an
/// EIP-1271 contract wallet takes.
pub fn TypedData::digest(
  self : TypedData,
) -> @types.Hex raise @types.CodecError {
  let cache : Map[String, Bytes] = Map([])
  let domain_sep = domain_separator_bytes(self.domain, cache~)
  let message_hash = @keccak.keccak256(
    encode_data(self.types, self.primary_type, self.message, cache~),
  )
  // `0x19 0x01` then the two 32-byte hashes
  let signed = Bytes::makei(2 + 2 * @codec.WORD_BYTES, i => {
    if i == 0 {
      b'\x19'
    } else if i == 1 {
      b'\x01'
    } else if i < 2 + @codec.WORD_BYTES {
      domain_sep[i - 2]
    } else {
      message_hash[i - 2 - @codec.WORD_BYTES]
    }
  })
  @types.Hex::from_bytes(@keccak.keccak256(signed))
}

///|
fn domain_separator_bytes(
  domain : TypedDataDomain,
  cache? : Map[String, Bytes] = Map([]),
) -> Bytes raise @types.CodecError {
  let types : Map[String, Array[TypedDataField]] = Map([
    (DOMAIN_TYPE, domain.fields()),
  ])
  @keccak.keccak256(encode_data(types, DOMAIN_TYPE, domain.to_json(), cache~))
}

///|
fn encode_type(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
) -> String raise @types.CodecError {
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
) -> String raise @types.CodecError {
  let members = fields_of(types, name)
    .map(f => "\{f.type_name} \{f.name}")
    .join(",")
  "\{name}(\{members})"
}

///|
/// A type's declared fields, or the error every caller here reports for a type
/// name the document never defined. Type names are strings and an EIP-712
/// document is often assembled at runtime, so this is an ordinary caller
/// mistake rather than a bug — one place owns the wording.
fn fields_of(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
) -> Array[TypedDataField] raise @types.CodecError {
  guard types.get(type_name) is Some(fields) else {
    raise @types.InvalidJson("\{type_name} is not defined")
  }
  fields
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
) -> Bytes raise @types.CodecError {
  @keccak.keccak256_string(encode_type(types, type_name))
}

///|
/// `type_hash`, computed once per type name.
///
/// mutable cache on moonbitlang
fn type_hash_cached(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  cache : Map[String, Bytes],
) -> Bytes raise @types.CodecError {
  match cache.get(type_name) {
    Some(hash) => hash
    None => {
      let hash = type_hash(types, type_name)
      cache[type_name] = hash
      hash
    }
  }
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
  cache? : Map[String, Bytes] = Map([]),
) -> Bytes raise @types.CodecError {
  guard value is Object(members) else {
    raise @types.InvalidJson("\{type_name} value must be an object")
  }
  let fields = fields_of(types, type_name)
  let words = [type_hash_cached(types, type_name, cache)]
  for f in fields {
    let v = match members.get(f.name) {
      Some(v) => v
      None => raise @types.InvalidJson("\{type_name}.\{f.name} is missing")
    }
    words.push(encode_value(types, f.type_name, v, cache~))
  }
  @codec.concat_words(words)
}

///|
/// One field's value, as the 32-byte word `encodeData` packs it into: an
/// array is the hash of its encoded elements, a struct is `hashStruct` —
/// `keccak256(encodeData(...))`, same as the top-level call — and anything
/// else is atomic.
fn encode_value(
  types : Map[String, Array[TypedDataField]],
  type_name : String,
  value : Json,
  cache? : Map[String, Bytes] = Map([]),
) -> Bytes raise @types.CodecError {
  if array_element(type_name) is Some((element, _)) {
    guard value is Array(items) else {
      raise @types.InvalidJson("expected an array for \{type_name}")
    }
    let words = items.map(item => encode_value(types, element, item, cache~))
    @keccak.keccak256(@codec.concat_words(words))
  } else if types.get(type_name) is Some(_) {
    @keccak.keccak256(encode_data(types, type_name, value, cache~))
  } else {
    encode_atomic(type_name, value)
  }
}

///|
/// An elementary value's word: `bool`/`address`/`uint*`/`int*` are left-padded
/// big-endian (`address` as a 160-bit unsigned integer), `bytes1..32` are
/// right-padded, and `string`/`bytes` are hashed rather than padded, since
/// they are dynamic.
fn encode_atomic(
  type_name : String,
  value : Json,
) -> Bytes raise @types.CodecError {
  match classify_elementary(type_name) {
    Some(String) =>
      match value {
        String(s) => @keccak.keccak256_string(s)
        _ => raise @types.InvalidJson("\{type_name} value must be a string")
      }
    Some(Bytes) =>
      match value {
        String(s) => @keccak.keccak256(@types.Hex::from_string(s).to_bytes())
        _ => raise @types.InvalidJson("\{type_name} value must be a hex string")
      }
    Some(Bool) =>
      match value {
        True => @codec.word_of_unsigned(BigInt::from_int(1))
        False => @codec.word_of_unsigned(BigInt::from_int(0))
        _ => raise @types.InvalidJson("\{type_name} value must be a boolean")
      }
    Some(@types.Address) =>
      match value {
        String(s) => @codec.word_left_pad(@types.Hex::from_string(s).to_bytes())
        _ =>
          raise @types.InvalidJson(
            "\{type_name} value must be an address string",
          )
      }
    Some(FixedBytes(_)) =>
      match value {
        String(s) =>
          @codec.word_right_pad(@types.Hex::from_string(s).to_bytes())
        _ => raise @types.InvalidJson("\{type_name} value must be a hex string")
      }
    Some(Uint(_)) =>
      @codec.word_of_unsigned(integer_value(value, path=type_name, type_name~))
    Some(Int(_)) =>
      @codec.word_of_unsigned(
        @codec.word_to_unsigned(
          integer_value(value, path=type_name, type_name~),
        ),
      )
    // `classify_elementary` never returns a compound variant — `encode_value`
    // took arrays and structs already — but the match still has to cover them
    Some(Array(_) | FixedArray(_, _) | Tuple(_)) | None =>
      raise @types.InvalidJson("\{type_name} is not an elementary type")
  }
}
