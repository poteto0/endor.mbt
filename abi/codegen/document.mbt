///|
/// One parameter of an ABI member, as the document declares it.
priv struct Param {
  /// What Solidity called it. Empty is legal and common — a getter's return
  /// value usually has no name at all.
  name : String
  /// The declared type, resolved into the `AbiType` the SDK encodes with.
  ty : @abi.AbiType
}

///|
/// A callable member of the ABI.
priv struct AbiFunction {
  name : String
  inputs : Array[Param]
  outputs : Array[Param]
  /// `nonpayable` or `payable` — it writes, so it is broadcast rather than
  /// evaluated. `view` and `pure` are reads.
  mutating : Bool
  /// `payable` — it accepts ether alongside the call.
  payable : Bool
}

///|
/// An event of the ABI. Only its signature matters here: what is generated is
/// the topic it is logged under.
priv struct AbiEvent {
  name : String
  inputs : Array[Param]
}

///|
/// Everything in an ABI document this generator has anything to say about.
///
/// `constructor`, `receive`, `fallback` and `error` entries are dropped while
/// reading rather than reported as skipped: a preset wraps a contract that is
/// *already deployed*, so there is nothing for it to generate from them, and
/// listing them as casualties would be noise.
priv struct Document {
  functions : Array[AbiFunction]
  events : Array[AbiEvent]
}

///|
/// Read an ABI document: the JSON array a compiler emits.
///
/// A malformed member stops the whole document rather than being stepped over.
/// The distinction this package draws throughout is between *what the ABI spec
/// does not allow* and *what this generator declines to translate*: the first
/// means the file is not an ABI and nothing read out of it can be trusted, the
/// second is a judgement call about one member and belongs in `skipped`. Only
/// the first raises.
fn Document::parse(abi_json : String) -> Document raise CodegenError {
  let json = @json.parse(abi_json) catch {
    e => raise InvalidJson("not JSON: \{e}")
  }
  guard json is Array(members) else {
    raise InvalidJson("an ABI is a JSON array of members")
  }
  let functions = []
  let events = []
  for i, entry in members {
    guard entry is Object(fields) else {
      raise InvalidAbi("member \{i} is not an object")
    }
    // the ABI spec makes `type` default to `function`
    let kind = match fields.get("type") {
      None => "function"
      Some(String(s)) => s
      Some(_) => raise InvalidAbi("member \{i} has a non-string `type`")
    }
    match kind {
      "function" => functions.push(read_function(fields, at=i))
      "event" => events.push(read_event(fields, at=i))
      _ => ()
    }
  }
  { functions, events }
}

///|
/// One `"type": "function"` entry.
///
/// `stateMutability` is what decides whether the generated method reads or
/// writes, and getting it wrong is expensive in one direction: a getter treated
/// as a write prompts the user and costs gas to read a number. Hence the
/// fallback to the pre-0.6 `constant` flag — an older ABI that says nothing
/// about mutability at all is treated as writing, which is the safe way to be
/// wrong.
fn read_function(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiFunction raise CodegenError {
  let name = read_name(fields, at~, kind="function")
  let mutability = match fields.get("stateMutability") {
    Some(String(s)) => s
    // pre-0.6 ABIs say `constant: true` instead
    None =>
      if fields.get("constant") is Some(True) {
        "view"
      } else {
        "nonpayable"
      }
    Some(_) =>
      raise InvalidAbi("function `\{name}` has a non-string `stateMutability`")
  }
  {
    name,
    inputs: read_params(fields, "inputs", of="function `\{name}`"),
    outputs: read_params(fields, "outputs", of="function `\{name}`"),
    mutating: !(mutability is ("view" | "pure")),
    payable: mutability == "payable",
  }
}

///|
/// One `"type": "event"` entry. Only the name and the parameter types are
/// read: an event's `indexed` flags decide which arguments land in `topics`
/// rather than in `data`, and nothing generated from this ABI decodes a log
/// yet, so nothing here would use them.
fn read_event(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiEvent raise CodegenError {
  let name = read_name(fields, at~, kind="event")
  { name, inputs: read_params(fields, "inputs", of="event `\{name}`") }
}

///|
/// A member's `name`, which is not optional for anything this reads: a
/// constructor or a fallback has no name and is dropped before it gets here, so
/// a nameless function or event is a truncated document rather than a legal
/// one.
///
/// A name that is not a Solidity identifier is refused for the same reason, and
/// it is refused *here* rather than where the name is used. The name is the one
/// thing out of an ABI that this package writes into source text verbatim —
/// `name="…"`, `what="…"`, and the signature in every doc comment — so a name
/// holding a quote or a newline does not merely fail to compile, it closes the
/// string literal and keeps writing, in a file the caller then hands to the
/// compiler. Checking it at the door is what makes that unrepresentable: no
/// emitter downstream can be written that forgets to.
///
/// Note which side of the line this falls on. It raises rather than skipping,
/// because a member named `"a\"; …"` is not a member a compiler emitted and the
/// rest of the document is no more trustworthy than that one. A name that *is*
/// a Solidity identifier but not a MoonBit one — `match`, `type` — is the
/// generator's own limit and is still skipped, in `function_block`.
fn read_name(
  fields : Map[String, Json],
  at~ : Int,
  kind~ : String,
) -> String raise CodegenError {
  match fields.get("name") {
    Some(String(s)) if s != "" =>
      if is_abi_ident(s) {
        s
      } else {
        raise InvalidAbi(
          "the \{kind} at index \{at} has a `name` that is not an identifier",
        )
      }
    _ => raise InvalidAbi("the \{kind} at index \{at} has no `name`")
  }
}

///|
/// A member's `inputs` or `outputs`.
///
/// An absent key is an empty list, not an error: solc omits `outputs` entirely
/// on a function that returns nothing. An empty *name* is likewise normal —
/// most compiled ABIs name no return values and many name no arguments either
/// — which is why the name is carried through as a plain `String` and turned
/// into an identifier much later, where the position is known.
fn read_params(
  fields : Map[String, Json],
  key : String,
  of~ : String,
) -> Array[Param] raise CodegenError {
  // `outputs` is simply absent on a function that returns nothing
  guard fields.get(key) is Some(value) else { return [] }
  guard value is Array(items) else {
    raise InvalidAbi("\{of} has a `\{key}` that is not an array")
  }
  let params = []
  for item in items {
    guard item is Object(param) else {
      raise InvalidAbi("\{of} has a `\{key}` entry that is not an object")
    }
    let name = match param.get("name") {
      Some(String(s)) => s
      None => ""
      Some(_) =>
        raise InvalidAbi("\{of} has a parameter with a non-string name")
    }
    params.push({ name, ty: read_type(param, of~) })
  }
  params
}

///|
/// Resolve a parameter's declared `type` (plus its `components`, for a tuple)
/// into an `AbiType`.
///
/// It goes through `AbiType` rather than keeping the Solidity spelling around
/// because that is what validates: `uint7` and `bytes33` parse fine as strings
/// and are types no contract can have, and `AbiType::name` is what says so.
fn read_type(
  param : Map[String, Json],
  of~ : String,
) -> @abi.AbiType raise CodegenError {
  guard param.get("type") is Some(String(solidity)) else {
    raise InvalidAbi("\{of} has a parameter with no `type`")
  }
  let ty = solidity_type(solidity, param.get("components"), of~)
  // a type that cannot be named is a type that cannot exist
  let _ = ty.name() catch {
    e =>
      raise InvalidAbi(
        "\{of} declares `\{solidity}`, which is not a type: \{e}",
      )
  }
  ty
}

///|
/// Resolve one Solidity type name, recursively.
///
/// Array suffixes are peeled from the right because that is how they nest:
/// `uint256[2][]` is a dynamic array *of* `uint256[2]`, so the last bracket
/// pair is the outermost type. Reading them left to right — the way they are
/// written — gets that backwards, and the resulting canonical name hashes to a
/// selector for a function with different parameters.
fn solidity_type(
  solidity : String,
  components : Json?,
  of~ : String,
) -> @abi.AbiType raise CodegenError {
  let unknown = () => {
    CodegenError::InvalidAbi(
      "\{of} declares `\{solidity}`, which is not an ABI type",
    )
  }
  if solidity.has_suffix("]") {
    guard solidity.rev_find("[") is Some(open) else { raise unknown() }
    let elem = solidity_type(solidity[:open].to_owned(), components, of~)
    let size = solidity[open + 1:solidity.length() - 1]
    if size == "" {
      return Array(elem)
    }
    let k = @string.parse_int(size) catch { _ => raise unknown() }
    return FixedArray(elem, k)
  }
  match solidity {
    "address" => Address
    "bool" => Bool
    "string" => String
    "bytes" => Bytes
    "uint" => Uint(256)
    "int" => Int(256)
    "tuple" => {
      guard components is Some(Array(items)) else {
        raise InvalidAbi("\{of} declares a tuple with no `components`")
      }
      let elems = []
      for item in items {
        guard item is Object(component) else {
          raise InvalidAbi("\{of} has a tuple component that is not an object")
        }
        elems.push(read_type(component, of~))
      }
      Tuple(elems)
    }
    _ =>
      if solidity.strip_prefix("uint") is Some(bits) {
        Uint(@string.parse_int(bits) catch { _ => raise unknown() })
      } else if solidity.strip_prefix("int") is Some(bits) {
        Int(@string.parse_int(bits) catch { _ => raise unknown() })
      } else if solidity.strip_prefix("bytes") is Some(n) {
        FixedBytes(@string.parse_int(n) catch { _ => raise unknown() })
      } else {
        raise unknown()
      }
  }
}
