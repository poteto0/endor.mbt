///|
/// A Solidity name as a MoonBit type name: `erc20` becomes `Erc20`, `my_token`
/// becomes `MyToken`.
///
/// This is how `endor-cli abi` turns an input file's name into the name of the
/// struct generated from it, and it lives here rather than in the CLI because
/// it is a rule about the generated code.
///
/// ```
/// inspect(@codegen.pascal_case("erc20"), content="Erc20")
/// inspect(@codegen.pascal_case("my-token.abi"), content="MyTokenAbi")
/// ```
pub fn pascal_case(name : String) -> String {
  let out = StringBuilder::new()
  let mut fresh = true
  for c in name {
    if c is ('_' | '-' | '.' | ' ') {
      fresh = true
    } else if fresh {
      out.write_char(c.to_ascii_uppercase())
      fresh = false
    } else {
      out.write_char(c.to_ascii_lowercase())
    }
  }
  out.to_string()
}

///|
/// A Solidity name as a MoonBit function name: `balanceOf` becomes
/// `balance_of`, `DOMAIN_SEPARATOR` becomes `domain_separator`.
///
/// A word boundary is where a capital follows a lowercase or a digit, or where
/// a capital is followed by a lowercase — which keeps runs of capitals
/// (`DOMAIN`) together instead of spelling them out letter by letter.
///
/// ```
/// inspect(@codegen.snake_case("transferFrom"), content="transfer_from")
/// ```
pub fn snake_case(name : String) -> String {
  let chars = name.to_array()
  let out = StringBuilder::new()
  let mut last_underscore = true // suppress a leading underscore
  for i, c in chars {
    if c.is_ascii_uppercase() {
      let prev_is_word = i > 0 &&
        (chars[i - 1].is_ascii_lowercase() || chars[i - 1].is_ascii_digit())
      let next_is_lower = i + 1 < chars.length() &&
        chars[i + 1].is_ascii_lowercase()
      if !last_underscore && (prev_is_word || next_is_lower) {
        out.write_char('_')
      }
      out.write_char(c.to_ascii_lowercase())
      last_underscore = false
    } else if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      out.write_char(c)
      last_underscore = false
    } else if !last_underscore {
      out.write_char('_')
      last_underscore = true
    }
  }
  out.to_string()
}

///|
/// Whether a string is a Solidity identifier: what a member's `name` is allowed
/// to be, and therefore what may be written into generated source verbatim.
///
/// Not the same question as `is_value_ident`: `snake_case` maps unknown
/// characters to `_`, so the bytes that reach the source text are what is
/// checked, not the bytes derived from them. `$` is inert in MoonBit source.
fn is_abi_ident(name : String) -> Bool {
  @codec.is_solidity_ident(name)
}

///|
/// Whether a string can be spelled as a MoonBit value identifier — and is not
/// a keyword, which would parse as something else entirely.
///
/// MoonBit's spelling is Solidity's minus `$`, which MoonBit has no character
/// for, plus the keywords: writing it as that difference is what keeps the
/// character class itself in one place.
fn is_value_ident(name : String) -> Bool {
  @codec.is_solidity_ident(name) &&
  !name.iter().any(c => c == '$') &&
  !keywords.contains(name)
}

///|
/// Whether a string can be spelled as a MoonBit type identifier: a value
/// identifier that starts with a capital.
fn is_type_ident(name : String) -> Bool {
  is_value_ident(name) && name.get_char(0) is Some(c) && c.is_ascii_uppercase()
}

///|
/// The words a generated identifier must not collide with. Overshooting is
/// harmless — a name in here is only ever suffixed with `_` — while missing
/// one emits source that does not parse.
let keywords : Set[String] = Set::Set(
  [
    "as", "async", "break", "catch", "const", "continue", "defer", "derive", "else",
    "enum", "extern", "false", "fn", "fnalias", "for", "guard", "if", "impl", "in",
    "init", "is", "let", "loop", "match", "mut", "noraise", "not", "pub", "priv",
    "raise", "return", "struct", "suberror", "test", "trait", "traitalias", "true",
    "try", "type", "typealias", "using", "while", "with",
  ][:],
)

///|
/// The same name, moved out of the way of everything already in scope.
///
/// A generated parameter competes with MoonBit's keywords and with what the
/// template binds (`self`, `provider`, `from`, `value`), so Solidity's
/// `transferFrom(address from, …)` has to spell its first parameter something
/// else. Suffixing `_` stays closest to what the ABI said.
fn dodge(name : String, taken : Set[String]) -> String {
  let mut out = name
  while taken.contains(out) || keywords.contains(out) {
    out = out + "_"
  }
  out
}
