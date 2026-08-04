///|
/// One parameter of an ABI member, as the document declares it.
priv struct Param {
  /// What Solidity called it. Empty is legal and common — a getter's return
  /// value usually has no name at all.
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
/// The `constructor` entry: what a deployment has to encode behind the creation
/// code, and whether it may be handed ether.
///
/// A contract that declares no constructor has one all the same — it takes
/// nothing and is not payable — so this is not an option. The absence of the
/// entry and `constructor()` are the same fact about deploying, and folding
/// them together here is what keeps that out of the emitter.
priv struct AbiConstructor {
  inputs : Array[Param]
  /// `payable` — the constructor accepts ether as the contract is created.
  payable : Bool
}

///|
/// The creation code a document carried, or why there is no `deploy` to
/// generate from it.
///
/// Three cases rather than an option, because "there was never any code here"
/// and "there was code and it cannot be deployed" are different things to tell
/// the caller: the first is a bare ABI document and costs no comment, the
/// second is an artifact whose bytecode this generator will not put on the
/// wire and belongs in `skipped` with its reason.
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
///
/// `receive`, `fallback` and `error` entries are dropped while reading rather
/// than reported as skipped: there is nothing to generate from them, and
/// listing them as casualties would be noise.
priv struct Document {
  functions : Array[AbiFunction]
  events : Array[AbiEvent]
  ctor : AbiConstructor
  creation_code : CreationCode
}

///|
/// Read a document: either the JSON array of ABI members a compiler emits, or
/// a compiler *artifact* — the object that carries that array together with the
/// creation code compiled from the same source.
///
/// Both are accepted because they are the same document at different widths,
/// and which one a caller has says what can be generated rather than whether
/// anything can: an ABI array describes a contract that is already deployed, an
/// artifact also says how to deploy one.
///
/// A malformed member stops the whole document rather than being stepped over.
/// The distinction this package draws throughout is between *what the ABI spec
/// does not allow* and *what this generator declines to translate*: the first
/// means the file is not an ABI and nothing read out of it can be trusted, the
/// second is a judgement call about one member and belongs in `skipped`. Only
/// the first raises.
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
  { functions, events, ctor, creation_code }
}

///|
/// A compiler artifact: the ABI array and the creation code, out of whichever
/// shape the compiler wrote them in.
///
/// The shapes are the same document as spelled by four tools —
/// `solc --combined-json abi,bin` (`abi` / `bin`, wrapped in `contracts`),
/// solc's standard JSON (`abi` / `evm.bytecode.object`, wrapped twice), a
/// Foundry artifact (`abi` / `bytecode.object`) and a Hardhat one
/// (`abi` / `bytecode`) — so they are read in one place and everything above
/// this sees one document.
fn read_artifact(
  fields : Map[String, Json],
) -> (Array[Json], CreationCode) raise CodegenError {
  let (abi, contract) = single_contract(fields)
  (read_members(abi), read_creation_code(contract))
}

///|
/// The one contract an artifact describes: its `abi`, and the object that key
/// was found in, which is also where the creation code is.
///
/// The two come back together because finding one *is* finding the other —
/// `abi` is what identifies a contract among the shapes below, so answering
/// with the map alone would leave the caller re-asking for a key this has
/// already proved is there, and writing an error for the case that cannot
/// happen.
///
/// A per-contract artifact *is* that object; `--combined-json` and standard
/// JSON instead wrap one or more of them in `contracts`, keyed by
/// `File.sol:Name` or by file and then name. Several contracts raise rather
/// than picking one: the caller names the struct that is generated, so
/// choosing which contract to give that name to would be this generator
/// guessing at the one thing it was told.
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
/// An artifact's `abi`.
///
/// A JSON string holding the array is what `solc --combined-json` wrote before
/// 0.8.10, and it is still the shape in every artifact produced by one — so it
/// is parsed rather than refused. Anything else is a document this cannot read.
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
/// The creation code out of an artifact, validated as something a generated
/// file can put on the wire.
///
/// It is checked here, once, rather than left for the compiler the caller runs
/// afterwards or — worse — for the node: what is emitted is a
/// `Hex::from_string` over a literal, and a literal that is not hex would turn
/// a bad artifact into generated code that aborts at run time.
///
/// It is checked *by `Hex::from_string` itself*, which is what makes that
/// `abort` unreachable by construction rather than by two statements of the
/// same grammar agreeing. `Hex` is where the prefix, the alphabet and the even
/// length are stated, and the generated file calls exactly this function on
/// exactly this string — so what is embedded is the `Hex` that came back,
/// normal form and all, rather than the digits that went in.
fn read_creation_code(
  contract : Map[String, Json],
) -> CreationCode raise CodegenError {
  guard bytecode_field(contract) is Some(value) else { return Absent }
  // no compiler writes a `bytecode` that is not a string, so this is a
  // corrupt document rather than one this generator declines to translate
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
      // a library the compiler could not resolve is left as `__$<hash>$__` in
      // the middle of the code — deployable-looking and not deployable. `_` is
      // not a hex digit, so it arrives here, and looking for it only once the
      // string is known bad keeps the scan off every valid artifact's path
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
/// Wherever the compiler put the creation code.
///
/// Answered as `Json` rather than as a string so that a key that is present
/// and holds something else is reported instead of read as absent: an artifact
/// that says `bytecode` and means it deserves an error, not silence.
///
/// The three places are tried in order and the first that holds anything wins,
/// written flat rather than nested so that the fourth compiler to want a key
/// here is one line rather than another level of `match`.
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
/// The `constructor` entry.
///
/// Its `name` is not read because it has none, and its `outputs` are not read
/// because a constructor returns the contract rather than a value. What is left
/// is what a deployment needs: the arguments to encode, and whether ether may
/// ride along.
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
/// A member's declared `stateMutability`, or `None` for one that declares none.
///
/// Absent is answered rather than defaulted because the two callers default it
/// differently: a function with no `stateMutability` falls back to the pre-0.6
/// `constant` flag and a constructor to `payable`, and those are the *only*
/// things they do differently with it. Present-but-not-a-string is the same
/// mistake for both — a document no compiler wrote — so it is refused once,
/// here.
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
/// flags that say which half of the log each one is in, and whether it is
/// anonymous — which is what decides whether anything can be generated from it
/// at all.
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
    params.push({
      name,
      ty: read_type(param, of~),
      // only an event's parameters carry it, and a document that puts it on a
      // function's is answered the same way as one that leaves it off an
      // event's: not indexed. `indexed` means "went into `topics`", and
      // nothing but an event has topics
      indexed: param.get("indexed") is Some(True),
    })
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
