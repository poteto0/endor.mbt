///|
/// A MoonBit source file rendered from an ABI, and what did not fit in it.
///
/// `skipped` is the half a caller must not throw away: the generator refuses
/// to emit a function it cannot type honestly, so a member missing from `code`
/// has its reason here — and in a comment in `code` itself, for whoever reads
/// the file later without the CLI's output in front of them.
pub(all) struct Generated {
  /// The generated MoonBit source.
  code : String
  /// The canonical signature of every ABI member that became a method, in the
  /// order they were emitted — `balanceOf(address)`, `Transfer(address,address,uint256)`.
  ///
  /// This is what the generated file *dispatches to*, which is not something
  /// its source text answers without being read as MoonBit: a caller checking
  /// that a preset really covers the interface it was generated from compares
  /// these, and a caller hashing them gets exactly the selectors the file will
  /// put on the wire.
  members : Array[String]
  /// One line per ABI member left out, saying which and why.
  skipped : Array[String]
  /// Whether the file holds a `deploy`, which is whether the document was an
  /// artifact carrying creation code this generator would put on the wire.
  ///
  /// False for a bare ABI document — there is nothing to deploy, and nothing
  /// was left out either. False *with* a line in `skipped` for an artifact
  /// whose bytecode cannot be deployed: unlinked libraries, an interface that
  /// compiled to none, a constructor taking a type this generator does not
  /// translate.
  deploys : Bool
}

///|
/// Render a contract preset from an ABI document.
///
/// **Experimental.** What comes out is a `pub struct <name>` wrapping a
/// `@contract.Contract`, a `<name>::new(address)`, and one method per ABI
/// function — reads through `Contract::call` with the answer decoded, writes
/// through `Contract::send` — plus a topic getter per event. It is the shape
/// `@erc20.Erc20` is hand-written in, produced mechanically.
///
/// It generates only what it can type unambiguously: parameters and single
/// return values of `address`, `bool`, `string`, `uintN` and `intN`. A member
/// using anything else — `bytes`, `bytesN`, arrays, tuples, several return
/// values — is **skipped**, not approximated: emitting a plausible-looking
/// wrong signature would be worse than emitting nothing, and
/// `@contract.Contract::call` still reaches it by hand. Events are exempt,
/// since a topic needs only the signature; `fallback`, `receive` and `error`
/// entries are dropped, since nothing generated dispatches to them.
///
/// `document` is either the JSON array of ABI members or a compiler
/// **artifact** holding one — `solc --combined-json abi,bin`, solc's standard
/// JSON, a Foundry or Hardhat artifact. An artifact also carries the creation
/// code, and then two more things are generated: a `creation_code()` and a
/// `deploy` over `@contract.deploy`, which takes the constructor's arguments
/// and answers with the contract it created.
///
/// ```
/// let out = @codegen.generate("Erc20", abi_json)
/// println(out.code)
/// for line in out.skipped {
///   println("skipped: \{line}")
/// }
/// ```
pub fn generate(
  name : String,
  document : String,
) -> Generated raise CodegenError {
  guard is_type_ident(name) else {
    raise InvalidName("`\{name}` is not a MoonBit type name")
  }
  let doc = Document::parse(document)
  let members = []
  let skipped = []
  let blocks = [preamble(name)]
  // the template's own methods, so nothing generated may take those names.
  // `deploy` and `creation_code` are reserved whether or not there is code to
  // put in them: which members a document generates must not change when the
  // same ABI is passed again as an artifact
  let taken = Set::Set(["new", "address", "creation_code", "deploy"][:])
  // the constructor comes first in the file for the same reason it comes first
  // in the contract's life
  let mut deploys = false
  match doc.creation_code {
    Absent => ()
    Unusable(reason) => skipped.push("`deploy`: \{reason}")
    Code(code) => {
      // the code goes in whether or not a `deploy` does: a constructor this
      // generator cannot type is exactly the caller who needs to reach
      // `@contract.deploy` themselves, and the bytes are what they need for it
      blocks.push(creation_code_block(name, code))
      match deploy_block(name, doc.ctor) {
        Ok(block) => {
          blocks.push(block)
          deploys = true
        }
        Err(reason) => skipped.push(reason)
      }
    }
  }
  for f in doc.functions {
    match function_block(name, f, taken) {
      Ok((signature, block)) => {
        members.push(signature)
        blocks.push(block)
      }
      Err(reason) => skipped.push(reason)
    }
  }
  for e in doc.events {
    match event_block(name, e, taken) {
      Ok((signature, block)) => {
        members.push(signature)
        blocks.push(block)
      }
      Err(reason) => skipped.push(reason)
    }
  }
  if !skipped.is_empty() {
    blocks.push(skipped_note(skipped))
  }
  { code: blocks.join("\n"), members, skipped, deploys }
}

///|
/// The `moon.pkg` a generated file needs in its directory. Emitting the source
/// without it would leave `@contract` and `@provider` unresolved, which is a
/// compile error rather than a runtime surprise — but still one the caller
/// should not have to work out from the error message.
///
/// ```
/// inspect(@codegen.moon_pkg().has_prefix("import {"), content="true")
/// ```
pub fn moon_pkg() -> String {
  (
    $|import {
    $|  "moonbitlang/core/bigint",
    $|  "moonbitlang/core/debug",
    $|  "poteto0/endor/types",
    $|  "poteto0/endor/abi",
    $|  "poteto0/endor/contract",
    $|  "poteto0/endor/provider",
    $|}
    $|
  )
}

///|
/// The file's header and the struct every generated method hangs off.
fn preamble(name : String) -> String {
  (
    $|// Generated by `endor-cli abi`. Do not edit — regenerate instead.
    $|
    $|///|
    $|/// `\{name}`, a contract at an address, generated from its ABI.
    $|///
    $|/// **Experimental — generated code.** The generator emits a method only
    $|/// where it can name the MoonBit types without guessing: parameters and
    $|/// single return values of `address`, `bool`, `string`, `uintN` and
    $|/// `intN`. Anything else in the ABI — `bytes`, `bytesN`, arrays, tuples,
    $|/// several return values — was left out rather than approximated, and is
    $|/// listed at the bottom of this file. Reach those through
    $|/// `@contract.Contract::call` / `send`, which take the `AbiType`s
    $|/// directly.
    $|///
    $|/// Amounts are `BigInt` in the contract's own units: this layer does no
    $|/// scaling, exactly as the rest of the SDK does none for `Wei`.
    $|///
    $|/// ```
    $|/// let contract = \{name}::new(address)
    $|/// let at = contract.address()
    $|/// ```
    $|pub struct \{name} {
    $|  priv contract : @contract.Contract
    $|} derive(Eq, @debug.Debug)
    $|
    $|///|
    $|/// Point at a deployed contract.
    $|pub fn \{name}::new(address : @types.Address) -> \{name} {
    $|  \{name}::{ contract: @contract.Contract::new(address) }
    $|}
    $|
    $|///|
    $|/// The address the calls go to.
    $|pub fn \{name}::address(self : \{name}) -> @types.Address {
    $|  self.contract.address()
    $|}
    $|
  )
}

///|
/// What a generated file says about what it does not contain.
fn skipped_note(skipped : Array[String]) -> String {
  let out = StringBuilder::new()
  out.write_string("// Not generated from this ABI:\n")
  for line in skipped {
    out.write_string("//   - \{line}\n")
  }
  out.write_string(
    "// Call these through `@contract.Contract::call` / `send`, which take the\n" +
    "// `AbiType`s directly.\n",
  )
  out.to_string()
}
