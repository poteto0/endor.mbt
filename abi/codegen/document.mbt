///|
/// One parameter of an ABI member, as the document declares it.
priv struct Param {
  /// What Solidity called it. Empty is legal and common.
  name : String
  /// The declared type, resolved into the `AbiType` the SDK encodes with.
  ty : @abi.AbiType
  /// `indexed` — an event parameter that went into the log's `topics` instead
  /// of its `data`. Always false for anything but an event.
  indexed : Bool
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
/// An event of the ABI: the topic its logs carry, and how to read one back.
priv struct AbiEvent {
  name : String
  inputs : Array[Param]
  /// `anonymous` — the log carries no signature hash in `topics[0]`, so
  /// nothing generated from this entry could match a log or decode one.
  anonymous : Bool
}

///|
/// An `error` of the ABI: what a `revert` can name, and the arguments it
/// carries. Nothing is called through it, so it carries every declared type,
/// including ones this generator would not put in a signature.
priv struct AbiErrorDecl {
  name : String
  inputs : Array[Param]
}

///|
/// The `constructor` entry: what a deployment encodes behind the creation
/// code, and whether it may be handed ether. Not an option — a contract that
/// declares none has one all the same, taking nothing and not payable.
priv struct AbiConstructor {
  inputs : Array[Param]
  /// `payable` — the constructor accepts ether as the contract is created.
  payable : Bool
}

///|
/// The creation code a document carried, or why there is no `deploy` to
/// generate from it. Three cases rather than an option: a document that never
/// claimed to carry code costs no comment, where one whose bytecode is
/// unusable belongs in `skipped` with its reason.
priv enum CreationCode {
  /// A bare ABI array, or an artifact with no bytecode in it: the document
  /// never claimed to carry code.
  Absent
  /// `0x`-prefixed hex, validated here so that the `Hex::from_string` in the
  /// generated file cannot fail.
  Code(String)
  /// There was bytecode, and this is why nothing is generated from it.
  Unusable(String)
}

///|
/// Everything in a document this generator has anything to say about.
/// `receive` and `fallback` are dropped while reading rather than reported as
/// skipped — there is nothing to generate from them.
priv struct Document {
  functions : Array[AbiFunction]
  events : Array[AbiEvent]
  errors : Array[AbiErrorDecl]
  ctor : AbiConstructor
  creation_code : CreationCode
}

///|
/// Read a document: either the JSON array of ABI members a compiler emits, or a
/// compiler *artifact*, which carries that array plus the creation code.
///
/// A malformed member stops the whole document — what the ABI spec does not
/// allow raises, because nothing in the file can be trusted; what this generator
/// declines to translate goes in `skipped`.
fn Document::parse(source : String) -> Document raise CodegenError {
  let json = @json.parse(source) catch {
    e => raise InvalidJson("not JSON: \{e}")
  }
  let (members, creation_code) = match json {
    Array(members) => (members, Absent)
    Object(fields) => read_artifact(fields)
    _ =>
      raise InvalidJson(
        "a document is a JSON array of ABI members or a compiler artifact holding one",
      )
  }
  let functions = []
  let events = []
  let errors = []
  // a contract that declares no constructor deploys with no arguments
  let mut ctor : AbiConstructor = { inputs: [], payable: false }
  let mut declared_ctor = false
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
      "error" => errors.push(read_error(fields, at=i))
      "constructor" => {
        // a contract has one constructor, so a document with two is not a
        // document a compiler wrote — and letting the last one win would
        // encode the wrong arguments into a deployment nobody can re-run
        guard !declared_ctor else {
          raise InvalidAbi("this ABI declares more than one constructor")
        }
        ctor = read_constructor(fields, at=i)
        declared_ctor = true
      }
      _ => ()
    }
  }
  { functions, events, errors, ctor, creation_code }
}

///|
/// A compiler artifact: the ABI array and the creation code, out of whichever
/// shape wrote them — `solc --combined-json`, solc standard JSON, Foundry or
/// Hardhat. Read in one place, so everything above sees one document.
fn read_artifact(
  fields : Map[String, Json],
) -> (Array[Json], CreationCode) raise CodegenError {
  let (abi, contract) = single_contract(fields)
  (read_members(abi), read_creation_code(contract))
}

///|
/// The one contract an artifact describes: its `abi`, and the object it was
/// found in, which is also where the creation code is.
///
/// A per-contract artifact *is* that object; `--combined-json` wraps them in
/// `contracts`. Several contracts raise rather than picking one — the caller
/// named the struct, so choosing which contract gets that name would be guessing.
fn single_contract(
  fields : Map[String, Json],
) -> (Json, Map[String, Json]) raise CodegenError {
  if fields.get("abi") is Some(abi) {
    return (abi, fields)
  }
  guard fields.get("contracts") is Some(Object(contracts)) else {
    raise InvalidJson(
      "this JSON object is not an artifact: it holds neither `abi` nor `contracts`",
    )
  }
  let found = []
  for key, value in contracts {
    guard value is Object(contract) else { continue }
    if contract.get("abi") is Some(abi) {
      found.push((key, abi, contract))
    } else {
      // standard JSON nests one level deeper: file, then contract name
      for name, nested in contract {
        if nested is Object(inner) && inner.get("abi") is Some(abi) {
          found.push(("\{key}:\{name}", abi, inner))
        }
      }
    }
  }
  match found {
    [(_, abi, contract)] => (abi, contract)
    [] => raise InvalidJson("this artifact's `contracts` holds no ABI")
    _ => {
      // sorted here rather than where they were collected: the order exists so
      // that this message reads the same twice, and nothing else consults it
      found.sort_by_key(entry => entry.0)
      raise InvalidJson(
        "this artifact holds \{found.length()} contracts (\{found.map(entry => entry.0).join(", ")}); generating one struct from it would mean choosing one — compile them apart, or pass one contract's artifact",
      )
    }
  }
}

///|
/// An artifact's `abi`. A JSON string holding the array is what
/// `solc --combined-json` wrote before 0.8.10, so it is parsed rather than
/// refused.
fn read_members(abi : Json) -> Array[Json] raise CodegenError {
  match abi {
    Array(members) => members
    String(nested) => {
      let json = @json.parse(nested) catch {
        e =>
          raise InvalidJson(
            "this artifact's `abi` is a string, and not JSON: \{e}",
          )
      }
      guard json is Array(members) else {
        raise InvalidJson("this artifact's `abi` is a string holding no array")
      }
      members
    }
    _ => raise InvalidJson("this artifact's `abi` is not an array of members")
  }
}

///|
/// The creation code out of an artifact, validated as something a generated file
/// can put on the wire — here rather than at run time in the caller's code.
///
/// `Hex::from_string` is where the prefix, the alphabet and the even length are
/// stated. What is embedded is the `Hex` that came back, normal form and all.
fn read_creation_code(
  contract : Map[String, Json],
) -> CreationCode raise CodegenError {
  guard bytecode_field(contract) is Some(value) else { return Absent }
  // no compiler writes a non-string `bytecode`: this is a corrupt document
  guard value is String(raw) else {
    raise InvalidAbi("this artifact's bytecode is not a string")
  }
  let hex = if raw.has_prefix("0x") { raw } else { "0x" + raw }
  // an interface and an abstract contract both compile to an ABI and to `""`,
  // which `Hex` would accept as the empty byte string
  guard hex != "0x" else {
    return Unusable(
      "its bytecode is empty — an interface or an abstract contract compiles to no creation code",
    )
  }
  let code = @types.Hex::from_string(hex) catch {
    InvalidLength(_) =>
      return Unusable("its bytecode has an odd number of hex digits")
    _ =>
      // an unresolved library is left as `__$<hash>$__`: deployable-looking and
      // not deployable. `_` is not a hex digit, so it arrives here.
      return Unusable(
        if hex.contains("__") {
          "its bytecode has unlinked library references (`__$…$__`) — link the libraries and regenerate"
        } else {
          "its bytecode is not hex"
        },
      )
  }
  Code(code.to_string())
}

///|
/// Wherever the compiler put the creation code. `Json` rather than a string,
/// so a key that is present but holds something else is reported rather than
/// read as absent.
fn bytecode_field(contract : Map[String, Json]) -> Json? {
  // Hardhat writes the string, Foundry wraps it in an object
  if unwrap_object(contract.get("bytecode")) is Some(value) {
    return Some(value)
  }
  // solc's standard JSON
  if contract.get("evm") is Some(Object(evm)) &&
    unwrap_object(evm.get("bytecode")) is Some(value) {
    return Some(value)
  }
  // `solc --combined-json bin`
  contract.get("bin")
}

///|
/// The `object` inside a bytecode field, for the compilers that wrap it, and
/// the field itself for the ones that do not.
fn unwrap_object(field : Json?) -> Json? {
  match field {
    Some(Object(wrapper)) => wrapper.get("object")
    other => other
  }
}

///|
/// The `constructor` entry: the arguments a deployment encodes, and whether
/// ether may ride along. It has no `name`, and returns the contract rather
/// than any `outputs`.
fn read_constructor(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiConstructor raise CodegenError {
  let payable = match
    read_mutability(fields, of="the constructor at index \{at}") {
    Some(mutability) => mutability == "payable"
    // pre-0.6 ABIs say `payable: true` instead
    None => fields.get("payable") is Some(True)
  }
  { inputs: read_params(fields, "inputs", of="the constructor"), payable }
}

///|
/// A member's declared `stateMutability`, or `None`. Absent rather than
/// defaulted, because the two callers default it differently: a function falls
/// back to the pre-0.6 `constant` flag, a constructor to `payable`.
fn read_mutability(
  fields : Map[String, Json],
  of~ : String,
) -> String? raise CodegenError {
  match fields.get("stateMutability") {
    Some(String(s)) => Some(s)
    None => None
    Some(_) => raise InvalidAbi("\{of} has a non-string `stateMutability`")
  }
}

///|
/// One `"type": "function"` entry. `stateMutability` decides whether the
/// generated method reads or writes; an ABI that says nothing about mutability
/// is treated as writing, which is the safe way to be wrong.
fn read_function(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiFunction raise CodegenError {
  let name = read_name(fields, at~, kind="function")
  let mutability = match read_mutability(fields, of="function `\{name}`") {
    Some(mutability) => mutability
    // pre-0.6 ABIs say `constant: true` instead
    None =>
      if fields.get("constant") is Some(True) {
        "view"
      } else {
        "nonpayable"
      }
  }
  let of = "function `\{name}`"
  {
    name,
    inputs: read_params(fields, "inputs", of~),
    outputs: read_params(fields, "outputs", of~),
    mutating: !(mutability is ("view" | "pure")),
    payable: mutability == "payable",
  }
}

///|
/// One `"type": "event"` entry: its name, its parameters with the `indexed`
/// flags saying which half of the log each is in, and whether it is anonymous.
fn read_event(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiEvent raise CodegenError {
  let name = read_name(fields, at~, kind="event")
  {
    name,
    inputs: read_params(fields, "inputs", of="event `\{name}`"),
    anonymous: fields.get("anonymous") is Some(True),
  }
}

///|
/// One `"type": "error"` entry: the name a revert carries and what rides with
/// it. `indexed` has no meaning here and is read as false, as it is everywhere
/// but an event.
fn read_error(
  fields : Map[String, Json],
  at~ : Int,
) -> AbiErrorDecl raise CodegenError {
  let name = read_name(fields, at~, kind="error")
  { name, inputs: read_params(fields, "inputs", of="error `\{name}`") }
}

///|
/// A member's `name`. Not optional: anything without one is dropped before it
/// gets here, so a nameless function or event is a truncated document.
///
/// A name that is not a Solidity identifier is refused rather than skipped — it
/// is written into source text verbatim, and a document holding one was not
/// written by a compiler. A MoonBit keyword is skipped in `function_block`.
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
/// A member's `inputs` or `outputs`. An absent key is an empty list — solc
/// omits `outputs` on a function that returns nothing — and so is an empty
/// name, which is why the name stays a plain `String` until `param_name` has
/// the position to fall back on.
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
    params.push({
      name,
      ty: read_type(param, of~),
      // `indexed` means "went into `topics`", and nothing but an event has
      // topics
      indexed: param.get("indexed") is Some(True),
    })
  }
  params
}

///|
/// Resolve a parameter's declared `type` (plus its `components`, for a tuple)
/// into an `AbiType`, which is what validates it: `uint7` and `bytes33` parse
/// fine as strings and are types no contract can have.
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
/// Resolve one Solidity type name, recursively. Array suffixes are peeled from
/// the right, because that is how they nest: `uint256[2][]` is a dynamic array
/// *of* `uint256[2]`.
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
