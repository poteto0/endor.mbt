///|
/// How one ABI type is spelled on all four sides of a generated call.
///
/// The four spellings have to agree or the emitted file does not compile, so
/// they are decided in one place: an `address` parameter is `@types.Address`
/// in the signature, `Address` in `inputs`, `Address(x)` in `args`, and read
/// back by `@contract.address_answer`.
priv struct Scalar {
  /// The type itself, which `type_literal` spells as the MoonBit source that
  /// goes in `inputs` / `outputs`.
  ty : @abi.AbiType
  /// The MoonBit type the caller passes or gets back.
  mbt : String
  /// The `AbiValue` constructor wrapping an argument.
  ctor : String
  /// The `@contract` helper that reads a single answer of this type.
  answer : String
}

///|
/// The spellings for an ABI type, or `None` for one this generator will not
/// translate.
///
/// The line is drawn at what has an obvious, lossless MoonBit counterpart.
/// `bytes` and `bytesN` are left out deliberately even though `Bytes` exists:
/// the ABI's `bytesN` is fixed-width and MoonBit's `Bytes` is not, so a
/// generated signature would promise a length it cannot enforce.
fn scalar(ty : @abi.AbiType) -> Scalar? {
  let (mbt, ctor, answer) = match ty {
    Address => ("@types.Address", "Address", "address_answer")
    Bool => ("Bool", "Bool", "bool_answer")
    String => ("String", "String", "string_answer")
    Uint(_) => ("BigInt", "Uint", "uint_answer")
    Int(_) => ("BigInt", "Int", "int_answer")
    _ => return None
  }
  Some({ ty, mbt, ctor, answer })
}

///|
/// One `AbiType` as MoonBit source, for every type the ABI has rather than only
/// the ones a generated *signature* can name.
///
/// The two are different questions: what a call can promise a caller in MoonBit
/// types is `scalar`'s judgement, while a declaration the SDK only ever reads
/// data against — a contract's `error`s — carries whatever the ABI said, and
/// leaving those out would drop exactly the errors that say most about what
/// went wrong.
///
/// It is spelled out here rather than taken from `AbiType`'s derived `Debug`,
/// which currently renders identically: `"\{ty}"` would make the derived debug
/// format load-bearing for source that has to compile, so a formatting change
/// nothing pins would silently emit uncompilable files. `codegen_test.mbt`
/// asserts the two agree, so "currently renders identically" stays a fact
/// rather than an assumption.
fn type_literal(ty : @abi.AbiType) -> String {
  match ty {
    Address => "Address"
    Bool => "Bool"
    String => "String"
    Bytes => "Bytes"
    Uint(bits) => "Uint(\{bits})"
    Int(bits) => "Int(\{bits})"
    FixedBytes(size) => "FixedBytes(\{size})"
    Array(inner) => "Array(\{type_literal(inner)})"
    FixedArray(inner, length) => "FixedArray(\{type_literal(inner)}, \{length})"
    Tuple(fields) => "Tuple([\{fields.map(type_literal).join(", ")}])"
  }
}

///|
/// The name a generated parameter gets: what Solidity called it, in snake
/// case, out of the way of everything the template already binds. A parameter
/// the ABI left unnamed — every argument of `allowance(address,address)` in a
/// compiled ERC-20 — is `arg0`, `arg1`, … by position.
fn param_name(param : Param, at~ : Int, taken : Set[String]) -> String {
  let base = snake_case(param.name)
  let base = if is_value_ident(base) { base } else { "arg\{at}" }
  let name = dodge(base, taken)
  taken.add(name)
  name
}

///|
/// Every parameter of a member as the pair the emitters take — the name it gets
/// in the generated source and how its type is spelled on all four sides — or
/// the reason the member cannot be generated at all.
///
/// `scope` is what the name has to dodge and is *added to* as it goes, so two
/// parameters the ABI named the same thing do not come out as one.
fn scalar_params(
  inputs : Array[Param],
  scope : Set[String],
  signature~ : String,
) -> Result[Array[(String, Scalar)], String] {
  let params = []
  for i, p in inputs {
    guard scalar(p.ty) is Some(s) else {
      let what = p.ty.name() catch { _ => "?" }
      return Err(
        "`\{signature}`: parameter \{i} is `\{what}`, which is not generated",
      )
    }
    params.push((param_name(p, at=i, scope), s))
  }
  Ok(params)
}

///|
/// One method, or the reason there is none.
///
/// `taken` carries the method names already emitted, so a Solidity overload —
/// two functions of the same name and different parameters, which MoonBit has
/// no way to spell — is reported rather than emitted twice.
///
/// A name MoonBit cannot spell is refused here, where a *parameter* of such a
/// name is instead renamed by `dodge`. The asymmetry is deliberate: a parameter
/// name is this generator's to choose — the ABI encodes arguments by position
/// and nothing on the wire remembers what they were called — while a method
/// name is what the caller looks up to find the function they mean. Renaming a
/// `type()` getter to `type_()` would leave a method whose name appears nowhere
/// in the ABI it came from, which is worse than saying it was not generated.
fn function_block(
  struct_name : String,
  f : AbiFunction,
  taken : Set[String],
) -> Result[(String, String), String] {
  // unreachable by construction — `read_type` already proved every one of
  // these types can be named, which is the only way `signature` fails. It is
  // still reported rather than aborted: a generator has no business killing
  // the process over an invariant it can simply decline to act on.
  let signature = @abi.signature(name=f.name, inputs=f.inputs.map(p => p.ty)) catch {
    e => return Err("`\{f.name}`: \{e}")
  }
  let fn_name = snake_case(f.name)
  guard is_value_ident(fn_name) else {
    return Err("`\{signature}`: its name is not spellable as a MoonBit method")
  }
  guard !taken.contains(fn_name) else {
    return Err(
      "`\{signature}`: `\{fn_name}` is already taken — MoonBit has no overloading",
    )
  }
  let scope = Set::Set(["self", "provider"][:])
  if f.mutating {
    scope.add("from")
    scope.add("value")
  }
  let params = match scalar_params(f.inputs, scope, signature~) {
    Ok(params) => params
    Err(reason) => return Err(reason)
  }
  let block = if f.mutating {
    sending_block(struct_name, f, signature~, fn_name~, params~)
  } else {
    guard f.outputs.length() == 1 else {
      return Err(
        "`\{signature}`: it returns \{f.outputs.length()} values, and only a single return value is generated",
      )
    }
    guard scalar(f.outputs[0].ty) is Some(out) else {
      let what = f.outputs[0].ty.name() catch { _ => "?" }
      return Err("`\{signature}`: it returns `\{what}`, which is not generated")
    }
    reading_block(struct_name, f, signature~, fn_name~, params~, out~)
  }
  taken.add(fn_name)
  Ok((signature, block))
}

///|
/// The `///|` marker, doc comment and function declaration through
/// `provider : P,` — the lines every generated method opens with, whatever it
/// then does. `reading_block`, `sending_block` and `deploy_block` diverge only
/// after this point: in what other parameters they add (`from~`, `value?`) and
/// in how they close the signature.
///
/// `receiver` is false for exactly one of them. `deploy` answers with the
/// contract it created, so there is no `self` to take: it is the one generated
/// function that is called before there is anything to call it on.
fn write_head(
  struct_name : String,
  fn_name : String,
  doc~ : String,
  from~ : Bool,
  params~ : Array[(String, Scalar)],
  receiver~ : Bool,
) -> StringBuilder {
  let head = StringBuilder::new()
  head.write_string("///|\n")
  head.write_string(doc)
  head.write_string(
    "pub async fn[P : @provider.Provider] \{struct_name}::\{fn_name}(\n",
  )
  if receiver {
    head.write_string("  self : \{struct_name},\n")
  }
  head.write_string("  provider : P,\n")
  // a write's `from~` precedes the ABI's own parameters, so that a caller
  // reading the signature sees who signs before what is signed
  if from {
    head.write_string("  from~ : @types.Address,\n")
  }
  for p in params {
    head.write_string("  \{p.0}~ : \{p.1.mbt},\n")
  }
  head
}

///|
/// A `view` / `pure` function: `eth_call`, with the single answer decoded.
fn reading_block(
  struct_name : String,
  f : AbiFunction,
  signature~ : String,
  fn_name~ : String,
  params~ : Array[(String, Scalar)],
  out~ : Scalar,
) -> String {
  let head = write_head(
    struct_name,
    fn_name,
    doc="/// `\{signature}` — reads.\n" +
      "///\n" +
      "/// It is evaluated against the chain's current state, so it costs nothing\n" +
      "/// and prompts no one.\n",
    from=false,
    params~,
    receiver=true,
  )
  let call = ["provider", "name=\"\{f.name}\""]
  call.append(abi_args(params))
  call.push("outputs=[\{type_literal(out.ty)}]")
  head.write_string(
    ") -> \{out.mbt} raise @contract.ContractError {\n" +
    "  @contract.\{out.answer}(\n" +
    call_expr("self.contract.call", call, indent=4, suffix=",") +
    "    what=\"\{f.name}\",\n" +
    "  )\n" +
    "}\n",
  )
  head.to_string()
}

///|
/// A `nonpayable` / `payable` function: a transaction, answering with its hash.
fn sending_block(
  struct_name : String,
  f : AbiFunction,
  signature~ : String,
  fn_name~ : String,
  params~ : Array[(String, Scalar)],
) -> String {
  let head = write_head(
    struct_name,
    fn_name,
    doc="/// `\{signature}` — writes.\n" +
      "///\n" +
      "/// It signs, so it prompts. The answer is the transaction's hash, not what\n" +
      "/// the function returned: a broadcast transaction has not run yet, and what\n" +
      "/// it did is in its receipt.\n",
    from=true,
    params~,
    receiver=true,
  )
  // `value?` closes the parameter list rather than joining `from~` ahead of it:
  // it is optional, and an optional parameter reads as an afterthought because
  // that is what it is
  if f.payable {
    head.write_string("  value? : @types.Wei,\n")
  }
  let send = ["provider", "from~", "name=\"\{f.name}\""]
  send.append(abi_args(params))
  if f.payable {
    send.push("value?")
  }
  head.write_string(
    ") -> @types.TxHash raise @contract.ContractError {\n" +
    call_expr("self.contract.send", send, indent=2, suffix="") +
    "}\n",
  )
  head.to_string()
}

///|
/// The `deploy` that sends the creation code, or the reason there is none.
///
/// This is the one generated function that is not a call to a contract: it
/// *makes* one. It is emitted separately from `creation_code_block`, and only
/// that one is unconditional: a constructor this generator cannot type costs
/// the `deploy` and must not also cost the literal, since handing those bytes
/// to `@contract.deploy` by hand is exactly what the caller is left with.
fn deploy_block(
  struct_name : String,
  ctor : AbiConstructor,
) -> Result[String, String] {
  // a constructor has no name; `constructor(uint256)` is how one is written,
  // and unlike a function's signature nothing hashes it — the arguments go
  // behind the creation code with no selector in front
  let signature = @abi.signature(
    name="constructor",
    inputs=ctor.inputs.map(p => p.ty),
  ) catch {
    e => return Err("`constructor`: \{e}")
  }
  let scope = Set::Set(["provider", "from", "value", "deployed"][:])
  let params = match scalar_params(ctor.inputs, scope, signature~) {
    Ok(params) => params
    Err(reason) =>
      return Err(
        "\{reason} — so no `deploy` was either; `creation_code()` still is, for `@contract.deploy`",
      )
  }
  let head = write_head(
    struct_name,
    "deploy",
    doc="/// Deploy a new `\{struct_name}` and answer with the one now on chain.\n" +
      "///\n" +
      "/// `\{signature}` — its arguments are ABI-encoded behind the creation code\n" +
      "/// above and sent as a transaction with no recipient, so it signs and\n" +
      "/// therefore prompts. It waits for the receipt: a deployment that reverted,\n" +
      "/// or one whose receipt names no address, raises rather than answering with\n" +
      "/// a `\{struct_name}` that is not there.\n",
    from=true,
    params~,
    receiver=false,
  )
  let deploy = ["provider", "from~", "bytecode~"]
  deploy.append(abi_args(params))
  if ctor.payable {
    head.write_string("  value? : @types.Wei,\n")
    deploy.push("value?")
  }
  head.write_string(
    ") -> \{struct_name} raise @contract.ContractError {\n" +
    // `creation_code` raises, so it is read before the call rather than inside
    // its argument list, where a `catch` would not fit on one line
    "  let bytecode = \{struct_name}::creation_code() catch {\n" +
    "    e => raise @contract.Deployment(\"creation code: \\{e}\")\n" +
    "  }\n" +
    call_expr("let deployed = @contract.deploy", deploy, indent=2, suffix="") +
    "  \{struct_name}::{ contract: deployed }\n" +
    "}\n",
  )
  Ok(head.to_string())
}

///|
/// The creation code as the generated file carries it.
///
/// Public, and therefore worth being: `deploy` passes none of
/// `@contract.deploy`'s waiting knobs (`confirmations`, `timeout`,
/// `poll_interval`) — restating them here would mean this template holding a
/// copy of that signature, to drift from it on the next parameter either one
/// grows. A caller who needs the wait described their own way calls
/// `@contract.deploy` with this, which is the same deployment with the waiting
/// left to them.
///
/// It raises rather than aborting (#113): the digits were validated as hex
/// before they were written here, so the only way to reach the failure is to
/// edit the literal in the generated file — which is the one thing its header
/// says not to do — but "unreachable" is not a reason for generated code to
/// hold the one `abort` the SDK does not.
///
/// The call stays on one line however long the code is — real creation code is
/// thousands of digits — because that is what `moon fmt` does with it: a string
/// literal is not something it can break, so wrapping the call around one only
/// produces a file the next `just fmt` unwraps.
fn creation_code_block(struct_name : String, code : String) -> String {
  (
    $|///|
    $|/// The creation code this file was generated from: what `\{struct_name}::deploy`
    $|/// puts on the wire, and what to hand `@contract.deploy` to deploy the same
    $|/// contract while waiting for it your own way.
    $|pub fn \{struct_name}::creation_code() -> @types.Hex raise @types.CodecError {
    $|  // validated as hex when this file was generated; it can only fail if
    $|  // this literal has been edited by hand
    $|  @types.Hex::from_string("\{code}")
    $|}
    $|
  )
}

///|
/// The contract's `error` declarations, as the array `new` hands to
/// `@contract.Contract`.
///
/// This is the one part of an ABI that has nowhere else to be stated: a call
/// says what it takes and what it returns, but nothing says what it may revert
/// with, and a revert names its error by a selector alone. With the array in
/// the file, a failed call comes back as `CustomError` carrying the name and
/// the decoded arguments; without it, as four bytes.
fn errors_block(struct_name : String, errors : Array[AbiErrorDecl]) -> String {
  let out = StringBuilder::new()
  out.write_string(
    (
      $|///|
      $|/// The errors this contract declares, in the order its ABI declares them.
      $|///
      $|/// `\{struct_name}::new` reads a reverting call against these, so
      $|/// `@contract.ContractError::CustomError` comes back named and decoded.
      $|pub fn \{struct_name}::errors() -> Array[@contract.ErrorDef] {
      $|  [
      $|
    ),
  )
  for e in errors {
    let inputs = e.inputs.map(p => type_literal(p.ty)).join(", ")
    out.write_string(
      record_expr(
        ["name: \"\{e.name}\"", "inputs: [\{inputs}]"],
        indent=4,
        suffix=",",
      ),
    )
  }
  out.write_string("  ]\n}\n")
  out.to_string()
}

///|
/// A call, laid out the way `moon fmt` would lay it out: on one line while it
/// fits inside the 80th column, and one argument per line with a trailing
/// comma once it does not.
///
/// Generated code that `moon fmt` immediately rewrites is generated code that
/// shows up as a diff in a repository that formats on commit, so the generator
/// does the wrapping itself rather than leaving it to be done again.
fn call_expr(
  callee : String,
  args : Array[String],
  indent~ : Int,
  suffix~ : String,
) -> String {
  let pad = " ".repeat(indent)
  let one_line = "\{pad}\{callee}(\{args.join(", ")})\{suffix}"
  if one_line.length() <= 80 {
    return one_line + "\n"
  }
  let out = StringBuilder::new()
  out.write_string("\{pad}\{callee}(\n")
  for arg in args {
    out.write_string("\{pad}  \{arg},\n")
  }
  out.write_string("\{pad})\{suffix}\n")
  out.to_string()
}

///|
/// A record literal, wrapped by the rule `call_expr` states: one line while it
/// fits, one field per line with a trailing comma once it does not.
///
/// `head` is what stands in front of the brace — a struct name and its `::`, or
/// nothing at all for a literal whose type is inferred.
fn record_expr(
  fields : Array[String],
  indent~ : Int,
  suffix~ : String,
  head? : String = "",
) -> String {
  let pad = " ".repeat(indent)
  let one_line = "\{pad}\{head}{ \{fields.join(", ")} }\{suffix}"
  if one_line.length() <= 80 {
    return one_line + "\n"
  }
  let out = StringBuilder::new()
  out.write_string("\{pad}\{head}{\n")
  for field in fields {
    out.write_string("\{pad}  \{field},\n")
  }
  out.write_string("\{pad}}\{suffix}\n")
  out.to_string()
}

///|
/// The topic an event's logs carry in `topics[0]`.
///
/// Events survive types that functions do not: what is generated is the
/// signature's hash, and every ABI type has a canonical name whether or not
/// this generator can pass one as an argument. Reading one of those logs back
/// is `decoder_block`, a separate answer about the same member: an event whose
/// arguments cannot be named keeps its topic, which is what a caller filters a
/// receipt's logs with before decoding them by hand.
fn event_block(
  struct_name : String,
  e : AbiEvent,
  taken : Set[String],
) -> Result[(String, String), String] {
  // as in `function_block`: unreachable, and declined rather than aborted
  let signature = @abi.signature(name=e.name, inputs=e.inputs.map(p => p.ty)) catch {
    err => return Err("event `\{e.name}`: \{err}")
  }
  // an anonymous event writes no signature hash, so there is no topic to
  // generate and nothing that could match one of its logs: its first topic is
  // already an argument, and nothing in the log says which event it belongs to
  guard !e.anonymous else {
    return Err(
      "event `\{signature}`: it is `anonymous`, so its logs carry no `topics[0]` to match or decode",
    )
  }
  let fn_name = snake_case(e.name) + "_topic"
  // unreachable as things stand — `read_name` has already proved the name is a
  // Solidity identifier, and no keyword survives a `_topic` suffix. Kept
  // because it costs a comparison and because the day the suffix changes is
  // not the day anyone re-derives that argument.
  guard is_value_ident(fn_name) else {
    return Err(
      "event `\{signature}`: its name is not spellable as a MoonBit method",
    )
  }
  guard !taken.contains(fn_name) else {
    return Err("event `\{signature}`: `\{fn_name}` is already taken")
  }
  taken.add(fn_name)
  Ok(
    (
      signature,
      (
        $|///|
        $|/// `topics[0]` of every log this event writes:
        $|/// `\{signature}`.
        $|///
        $|/// What a receipt's logs are matched against to find it.
        $|pub fn \{struct_name}::\{fn_name}() -> @types.Hex {
        $|  @abi.event_topic("\{signature}")
        $|}
        $|
      ),
    ),
  )
}

///|
/// The parts as a tuple — the types a decoder answers with, or the names it
/// binds. MoonBit has no one-element tuple, so a single part is itself: `(x)`
/// is `x`, and a decoder for a one-parameter event answers with that parameter
/// rather than with a tuple holding it.
fn tuple_of(parts : Array[String]) -> String {
  if parts.length() == 1 {
    parts[0]
  } else {
    "(" + parts.join(", ") + ")"
  }
}

///|
/// The method that reads one of this event's logs back as the arguments it was
/// emitted with, or the reason there is none.
///
/// It answers with a tuple of MoonBit values rather than with the
/// `Array[@abi.AbiValue]` `@abi.decode_log` hands back, which is the whole
/// difference between the generated decoder and calling that by hand — and the
/// reason it runs into the same limit every other generated method does: a
/// parameter this generator cannot name costs the decoder, and the event keeps
/// its topic regardless.
fn decoder_block(
  struct_name : String,
  e : AbiEvent,
  signature~ : String,
  taken : Set[String],
) -> Result[String, String] {
  let fn_name = "decode_" + snake_case(e.name)
  // spellable by construction, for `event_block`'s reason: a name that survived
  // `read_name` survives a prefix too. Taken, though, it can be — a contract
  // with a `decodeTransfer()` function is generated before any event is
  guard !taken.contains(fn_name) else {
    return Err("event `\{signature}`: `\{fn_name}` is already taken")
  }
  // an indexed `string` is the one type this generator can name and still must
  // not: what the topic holds is the `keccak256` of the value, so a generated
  // `String` would be a promise the log cannot keep
  for i, p in e.inputs {
    if p.indexed && p.ty is String {
      return Err(
        "event `\{signature}`: parameter \{i} is an indexed `string`, which a log holds only as its hash",
      )
    }
  }
  let params = match
    scalar_params(e.inputs, Set::Set(["log", "values"][:]), signature~) {
    Ok(params) => params
    Err(reason) => return Err(reason)
  }
  taken.add(fn_name)
  let answer = tuple_of(params.map(p => p.1.mbt))
  let bound = tuple_of(params.map(p => p.0))
  let out = StringBuilder::new()
  out.write_string(
    (
      $|///|
      $|/// One log of `\{signature}`,
      $|/// read back as the arguments it was emitted with: the indexed ones out
      $|/// of `topics`, the rest out of `data`, in the order the event declares
      $|/// them.
      $|///
      $|/// A log of another event raises rather than decoding — `topics[0]` is
      $|/// what tells them apart, and a receipt holds the logs of every contract
      $|/// the transaction touched.
      $|pub fn \{struct_name}::\{fn_name}(
      $|  log : @types.Log,
      $|) -> \{answer} raise @contract.ContractError {
      $|  let values = @abi.decode_log(
      $|    name="\{e.name}",
      $|    params=[
      $|
    ),
  )
  for i, p in params {
    out.write_string(
      "      { ty: \{type_literal(p.1.ty)}, indexed: \{e.inputs[i].indexed} },\n",
    )
  }
  let pattern = params.map(p => "\{p.1.ctor}(\{p.0})").join(", ")
  out.write_string(
    (
      $|    ],
      $|    topics=log.topics,
      $|    data=log.data,
      $|  ) catch {
      $|    e => raise @contract.Abi(e)
      $|  }
      $|  // unreachable: `decode_log` answers with the types named just above,
      $|  // or raises
      $|  guard values is [\{pattern}] else {
      $|    raise @contract.Abi(
      $|
    ),
  )
  // the message carries the signature, which can be any length, so whether it
  // fits on the line is not something this template can decide by looking
  out.write_string(
    call_expr(
      "@types.InvalidData",
      ["\"\{signature} did not decode as its own types\""],
      indent=6,
      suffix=",",
    ),
  )
  out.write_string(
    (
      $|    )
      $|  }
      $|  \{bound}
      $|}
      $|
    ),
  )
  Ok(out.to_string())
}

///|
/// The `inputs` and `args` arguments, or neither for a function that takes no
/// parameters — `Contract::call` and `send` both default them to empty, so a
/// generated method says nothing rather than saying `inputs=[], args=[]`.
///
/// They come back together because they have to *stay* together: `encode`
/// pairs them positionally, so the nth type and the nth value are one fact
/// about the nth parameter and are built from one walk over one list. Returned
/// as arguments rather than written, because whether a call fits on one line
/// is decided by `call_expr` after it has all of them.
///
/// The types are spelled out at every call site rather than hoisted into a
/// constant on the struct, because `Contract::call` hashes them into the
/// selector on each call — a generated method carries its own signature, and a
/// reader can see which function it dispatches to without following a
/// reference.
fn abi_args(params : Array[(String, Scalar)]) -> Array[String] {
  if params.is_empty() {
    return []
  }
  [
    "inputs=[\{params.map(p => type_literal(p.1.ty)).join(", ")}]",
    "args=[\{params.map(p => "\{p.1.ctor}(\{p.0})").join(", ")}]",
  ]
}
