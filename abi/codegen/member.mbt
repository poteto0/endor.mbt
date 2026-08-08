///|
/// How one ABI type is spelled on all four sides of a generated call. They
/// have to agree or the emitted file does not compile, so one place decides
/// them: `address` is `@types.Address`, `Address`, `Address(x)` and
/// `@contract.address_answer`.
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
/// translate. The line is drawn at a lossless MoonBit counterpart: `bytesN` is
/// fixed-width where `Bytes` is not, so it is left out.
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
/// One `AbiType` as MoonBit source, for every type the ABI has — wider than
/// `scalar`, because a declaration the SDK only reads against (a contract's
/// `error`s) carries whatever the ABI said.
///
/// Spelled out rather than taken from the derived `Debug`, which would make a
/// formatting change able to emit uncompilable files. `codegen_test.mbt`
/// asserts the two agree.
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
/// What Solidity called the parameter, in snake case, out of the way of what
/// the template already binds. One the ABI left unnamed is `arg0`, `arg1`, …
fn param_name(param : Param, at~ : Int, taken : Set[String]) -> String {
  let base = snake_case(param.name)
  let base = if is_value_ident(base) { base } else { "arg\{at}" }
  let name = dodge(base, taken)
  taken.add(name)
  name
}

///|
/// Every parameter as the (name, spelling) pair the emitters take, or the
/// reason the member cannot be generated. `scope` is added to as it goes, so
/// two parameters of the same name do not come out as one.
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
/// One method, or the reason there is none. `taken` holds the names already
/// emitted, so a Solidity overload is reported rather than emitted twice.
///
/// A method name MoonBit cannot spell is refused, where a *parameter* of such
/// a name is renamed instead: a parameter name is nowhere on the wire, but a
/// method name is what the caller looks up in the ABI.
fn function_block(
  struct_name : String,
  f : AbiFunction,
  taken : Set[String],
) -> Result[(String, String), String] {
  // unreachable — `read_type` already proved every type can be named. Reported
  // rather than aborted: a generator declines, it does not panic.
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
/// The lines every generated method opens with, down to `provider : P,`.
/// `reading_block`, `sending_block` and `deploy_block` diverge after this in
/// what parameters they add and how they close the signature.
///
/// `receiver` is false only for `deploy`, which is called before there is a
/// contract to call it on.
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
  // `from~` before the ABI's own parameters: who signs, then what is signed
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
  // `value?` closes the list: it is optional, and reads as one
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
/// Separate from `creation_code_block`, which is unconditional: a constructor
/// this generator cannot type costs the `deploy`, not the bytes the caller
/// then hands to `@contract.deploy` themselves.
fn deploy_block(
  struct_name : String,
  ctor : AbiConstructor,
) -> Result[String, String] {
  // a constructor has no name and nothing hashes this: the arguments go behind
  // the creation code with no selector in front
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
  let deploy = ["provider", "from~", "bytecode=\{struct_name}::creation_code()"]
  deploy.append(abi_args(params))
  if ctor.payable {
    head.write_string("  value? : @types.Wei,\n")
    deploy.push("value?")
  }
  head.write_string(
    ") -> \{struct_name} raise @contract.ContractError {\n" +
    call_expr("let deployed = @contract.deploy", deploy, indent=2, suffix="") +
    "  \{struct_name}::{ contract: deployed }\n" +
    "}\n",
  )
  Ok(head.to_string())
}

///|
/// The creation code as the generated file carries it.
///
/// Public, because `deploy` passes none of `@contract.deploy`'s waiting knobs:
/// a caller who needs the wait described their own way passes this to it.
///
/// A `Bytes` literal, not the hex string it was read from (#113):
/// `Hex::from_bytes` is total, so the generated function needs no `abort` and
/// no `raise` nothing can trigger.
fn creation_code_block(struct_name : String, code : String) -> String {
  (
    $|///|
    $|/// The creation code this file was generated from: what `\{struct_name}::deploy`
    $|/// puts on the wire, and what to hand `@contract.deploy` to deploy the same
    $|/// contract while waiting for it your own way.
    $|pub fn \{struct_name}::creation_code() -> @types.Hex {
    $|\{call_expr("@types.Hex::from_bytes", [bytes_literal(code)], indent=2, suffix="")}}
    $|
  )
}

///|
/// A `0x`-prefixed hex string as the `Bytes` literal holding the same bytes:
/// `"0x600a"` becomes `b"\\x60\\x0a"`. Every byte is escaped — a creation code is
/// not prose, and one rule reads more easily than two.
fn bytes_literal(code : String) -> String {
  let out = StringBuilder::new()
  out.write_string("b\"")
  // validated as `0x` + an even number of digits already, so these pair up
  let digits = code[2:]
  for i = 0; i < digits.length(); i = i + 2 {
    out.write_string("\\x")
    out.write_string(digits[i:i + 2].to_owned())
  }
  out.write_string("\"")
  out.to_string()
}

///|
/// The contract's `error` declarations, as the array `new` hands to
/// `@contract.Contract`. A revert names its error by selector alone, so with
/// this a failed call comes back as a named, decoded `CustomError` — without
/// it, as four bytes.
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
/// A call laid out the way `moon fmt` would: one line while it fits in 80
/// columns, one argument per line once it does not. Wrapping it here keeps the
/// generated file from showing up as a diff the first time it is formatted.
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
/// A record literal, wrapped by `call_expr`'s rule. `head` is what stands in
/// front of the brace — a struct name and its `::`, or nothing when the type
/// is inferred.
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
/// Events survive types functions do not: this generates the signature's hash,
/// and every ABI type has a canonical name. Reading such a log back is
/// `decoder_block`'s separate answer, so an event whose arguments cannot be
/// named still keeps the topic a caller filters logs with.
fn event_block(
  struct_name : String,
  e : AbiEvent,
  taken : Set[String],
) -> Result[(String, String), String] {
  // as in `function_block`: unreachable, declined rather than aborted
  let signature = @abi.signature(name=e.name, inputs=e.inputs.map(p => p.ty)) catch {
    err => return Err("event `\{e.name}`: \{err}")
  }
  // an anonymous event writes no signature hash: its first topic is already an
  // argument, so nothing in the log says which event it is
  guard !e.anonymous else {
    return Err(
      "event `\{signature}`: it is `anonymous`, so its logs carry no `topics[0]` to match or decode",
    )
  }
  let fn_name = snake_case(e.name) + "_topic"
  // unreachable — no keyword survives a `_topic` suffix. Kept for the day the
  // suffix changes.
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
/// The parts as a tuple. MoonBit has no one-element tuple, so a single part is
/// itself: a one-parameter event decodes to that parameter, not a tuple.
fn tuple_of(parts : Array[String]) -> String {
  if parts.length() == 1 {
    parts[0]
  } else {
    "(" + parts.join(", ") + ")"
  }
}

///|
/// The method that reads one of this event's logs back as the arguments it was
/// emitted with, or the reason there is none. It answers with a tuple of
/// MoonBit values rather than `@abi.decode_log`'s `Array[@abi.AbiValue]`, so a
/// parameter this generator cannot name costs the decoder — never the topic.
fn decoder_block(
  struct_name : String,
  e : AbiEvent,
  signature~ : String,
  taken : Set[String],
) -> Result[String, String] {
  let fn_name = "decode_" + snake_case(e.name)
  // spellable by construction, but takeable: a contract with a
  // `decodeTransfer()` function is generated before any event is
  guard !taken.contains(fn_name) else {
    return Err("event `\{signature}`: `\{fn_name}` is already taken")
  }
  // an indexed `string` is held in the topic as its `keccak256`, so a
  // generated `String` would be a promise the log cannot keep
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
  // the signature can be any length, so the wrapping is not decidable here
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
/// The `inputs` and `args` arguments, or neither when there are no parameters
/// — `Contract::call` and `send` default both to empty.
///
/// They come back together because `encode` pairs them positionally, and as
/// arguments rather than written text, because `call_expr` decides the
/// wrapping once it has them all.
fn abi_args(params : Array[(String, Scalar)]) -> Array[String] {
  if params.is_empty() {
    return []
  }
  [
    "inputs=[\{params.map(p => type_literal(p.1.ty)).join(", ")}]",
    "args=[\{params.map(p => "\{p.1.ctor}(\{p.0})").join(", ")}]",
  ]
}
