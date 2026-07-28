///|
/// How one ABI type is spelled on all four sides of a generated call.
///
/// The four spellings have to agree or the emitted file does not compile, so
/// they are decided in one place: an `address` parameter is `@types.Address`
/// in the signature, `Address` in `inputs`, `Address(x)` in `args`, and read
/// back by `@contract.address_answer`.
priv struct Scalar {
  /// The `AbiType` as MoonBit source — what goes in `inputs` / `outputs`.
  literal : String
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
  match ty {
    Address =>
      Some({
        literal: "Address",
        mbt: "@types.Address",
        ctor: "Address",
        answer: "address_answer",
      })
    Bool =>
      Some({ literal: "Bool", mbt: "Bool", ctor: "Bool", answer: "bool_answer" })
    String =>
      Some({
        literal: "String",
        mbt: "String",
        ctor: "String",
        answer: "string_answer",
      })
    Uint(bits) =>
      Some({
        literal: "Uint(\{bits})",
        mbt: "BigInt",
        ctor: "Uint",
        answer: "uint_answer",
      })
    Int(bits) =>
      Some({
        literal: "Int(\{bits})",
        mbt: "BigInt",
        ctor: "Int",
        answer: "int_answer",
      })
    _ => None
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
/// One method, or the reason there is none.
///
/// `taken` carries the method names already emitted, so a Solidity overload —
/// two functions of the same name and different parameters, which MoonBit has
/// no way to spell — is reported rather than emitted twice.
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
  let params = []
  for i, p in f.inputs {
    guard scalar(p.ty) is Some(s) else {
      let what = p.ty.name() catch { _ => "?" }
      return Err(
        "`\{signature}`: parameter \{i} is `\{what}`, which is not generated",
      )
    }
    params.push((param_name(p, at=i, scope), s))
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
/// A `view` / `pure` function: `eth_call`, with the single answer decoded.
fn reading_block(
  struct_name : String,
  f : AbiFunction,
  signature~ : String,
  fn_name~ : String,
  params~ : Array[(String, Scalar)],
  out~ : Scalar,
) -> String {
  let head = StringBuilder::new()
  head.write_string("///|\n")
  head.write_string("/// `\{signature}` — reads.\n")
  head.write_string("///\n")
  head.write_string(
    "/// It is evaluated against the chain's current state, so it costs nothing\n" +
    "/// and prompts no one.\n",
  )
  head.write_string(
    "pub async fn[P : @provider.Provider] \{struct_name}::\{fn_name}(\n",
  )
  head.write_string("  self : \{struct_name},\n")
  head.write_string("  provider : P,\n")
  for p in params {
    head.write_string("  \{p.0}~ : \{p.1.mbt},\n")
  }
  let call = ["provider", "name=\"\{f.name}\""]
  if !params.is_empty() {
    call.push("inputs=[\{inputs_of(params)}]")
    call.push("args=[\{args_of(params)}]")
  }
  call.push("outputs=[\{out.literal}]")
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
  let head = StringBuilder::new()
  head.write_string("///|\n")
  head.write_string("/// `\{signature}` — writes.\n")
  head.write_string("///\n")
  head.write_string(
    "/// It signs, so it prompts. The answer is the transaction's hash, not what\n" +
    "/// the function returned: a broadcast transaction has not run yet, and what\n" +
    "/// it did is in its receipt.\n",
  )
  head.write_string(
    "pub async fn[P : @provider.Provider] \{struct_name}::\{fn_name}(\n",
  )
  head.write_string("  self : \{struct_name},\n")
  head.write_string("  provider : P,\n")
  head.write_string("  from~ : @types.Address,\n")
  for p in params {
    head.write_string("  \{p.0}~ : \{p.1.mbt},\n")
  }
  if f.payable {
    head.write_string("  value? : @types.Wei,\n")
  }
  let send = ["provider", "from~", "name=\"\{f.name}\""]
  if !params.is_empty() {
    send.push("inputs=[\{inputs_of(params)}]")
    send.push("args=[\{args_of(params)}]")
  }
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
  let one_line = "\{pad}\{callee}(\{args.join(", ")})\{suffix}\n"
  if one_line.length() - 1 <= 80 {
    return one_line
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
/// The topic an event's logs carry in `topics[0]`.
///
/// Events survive types that functions do not: what is generated is the
/// signature's hash, and every ABI type has a canonical name whether or not
/// this generator can pass one as an argument.
fn event_block(
  struct_name : String,
  e : AbiEvent,
  taken : Set[String],
) -> Result[(String, String), String] {
  // as in `function_block`: unreachable, and declined rather than aborted
  let signature = @abi.signature(name=e.name, inputs=e.inputs.map(p => p.ty)) catch {
    err => return Err("event `\{e.name}`: \{err}")
  }
  let fn_name = snake_case(e.name) + "_topic"
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
      "///|\n" +
      "/// `topics[0]` of every log this event writes:\n" +
      "/// `\{signature}`.\n" +
      "///\n" +
      "/// What a receipt's logs are matched against to find it.\n" +
      "pub fn \{struct_name}::\{fn_name}() -> @types.Hex {\n" +
      "  @abi.event_topic(\"\{signature}\")\n" +
      "}\n",
    ),
  )
}

///|
/// The `inputs` argument: the ABI types, in order.
///
/// It is spelled out at every call site rather than hoisted into a constant on
/// the struct, because `Contract::call` hashes it into the selector on each
/// call — a generated method carries its own signature, and a reader can see
/// which function it dispatches to without following a reference.
fn inputs_of(params : Array[(String, Scalar)]) -> String {
  params.map(p => p.1.literal).join(", ")
}

///|
/// The `args` argument: each parameter wrapped in the `AbiValue` constructor
/// its type calls for. It has to line up with `inputs_of` element by element —
/// `encode` pairs them positionally — which is why both are built from the same
/// list rather than from the ABI twice.
fn args_of(params : Array[(String, Scalar)]) -> String {
  params.map(p => "\{p.1.ctor}(\{p.0})").join(", ")
}
