///|
/// Where `endor-cli abi` reads ABI documents from and writes MoonBit to.
///
/// This is `endor.yaml`, and it is the whole of it:
///
/// ```yaml
/// version: v0.3.0
/// abi:
///   in: ./abi
///   out: ./outputs
/// ```
pub(all) struct Config {
  /// The SDK version the project pins. Read and reported, not acted on: the
  /// generator emits source against whatever `poteto0/endor` the consuming
  /// module resolves.
  version : String?
  /// The directory of ABI documents to read.
  abi_in : String
  /// The directory to write generated MoonBit into. Created if missing.
  abi_out : String
}

///|
/// What can go wrong before any code is generated.
pub(all) suberror ConfigError {
  /// A line that is not `key: value`, or an indent this reader does not
  /// understand.
  Malformed(String)
  /// The file parsed, but does not say where the ABIs are or where the
  /// output goes.
  Incomplete(String)
} derive(Eq)

///|
pub impl Show for ConfigError with fn output(self, logger) {
  match self {
    Malformed(s) => logger.write_string("Malformed(\{s})")
    Incomplete(s) => logger.write_string("Incomplete(\{s})")
  }
}

///|
/// Read an `endor.yaml`.
///
/// This is **not** a YAML parser and is not meant to grow into one: it reads
/// the fixed two-level shape above — top-level `key: value`, and one level of
/// two-space-indented keys under a section — and nothing else. Flow
/// collections, anchors, multi-line scalars and lists are all unsupported, and
/// a document using them is rejected rather than half-understood. Unknown keys
/// are ignored, so a newer `endor.yaml` still works with an older CLI.
///
/// Comments are understood wherever YAML puts them, on their own line and
/// after a value, because a config file people are meant to edit by hand is a
/// config file people annotate — and a `#` swallowed into a path fails much
/// later, as a directory that is not there, naming a string nobody typed.
///
/// ```
/// let config = parse_config("abi:\n  in: ./abi\n  out: ./gen\n")
/// inspect(config.abi_in, content="./abi")
/// ```
pub fn parse_config(text : String) -> Config raise ConfigError {
  let mut section = ""
  let mut version = None
  let mut abi_in = None
  let mut abi_out = None
  for raw in text.split("\n") {
    let line = raw.trim_end(chars="\r").to_owned()
    if line.trim().is_empty() || line.trim().has_prefix("#") {
      continue
    }
    let indent = line.length() - line.trim_start(chars=" ").length()
    guard line.split_once(":") is Some((key, rest)) else {
      raise Malformed("`\{line.trim()}` is not `key: value`")
    }
    let key = key.trim().to_owned()
    let value = unquote(strip_comment(rest.trim().to_owned()))
    match indent {
      0 => {
        section = key
        if key == "version" {
          version = Some(value)
        }
      }
      2 =>
        match (section, key) {
          ("abi", "in") => abi_in = Some(value)
          ("abi", "out") => abi_out = Some(value)
          // forward compatibility: a key this CLI has never heard of is not
          // an error, it is a newer file
          _ => ()
        }
      _ =>
        raise Malformed(
          "`\{line.trim()}` is indented \{indent} spaces; expected 0 or 2",
        )
    }
  }
  guard abi_in is Some(abi_in) && abi_in != "" else {
    raise Incomplete("`abi.in` says nothing: there is no directory to read")
  }
  guard abi_out is Some(abi_out) && abi_out != "" else {
    raise Incomplete("`abi.out` says nothing: there is nowhere to write")
  }
  { version, abi_in, abi_out }
}

///|
/// A value with its trailing comment taken off.
///
/// The `#` has to be preceded by a space to start one, which is what keeps a
/// path like `./abi#2` whole — YAML draws the same line, and a directory whose
/// name has a `#` in it is likelier than a caller who wanted an empty value.
/// A quoted scalar is exempt up to its closing quote, so `"./a # b"` is a path
/// and `"./a" # b` is a path with a comment after it.
fn strip_comment(value : String) -> String {
  let start = if value.has_prefix("\"") || value.has_prefix("'") {
    let quote = value[:1].to_owned()
    match value[1:].to_owned().find(quote) {
      Some(close) => close + 2
      // an unterminated quote is not a comment to strip; `unquote` leaves it
      // alone too, and the caller sees the odd value they wrote
      None => return value
    }
  } else {
    0
  }
  match value[start:].to_owned().find(" #") {
    Some(at) => value[:start + at].trim_end(chars=" ").to_owned()
    None => value
  }
}

///|
/// YAML lets a scalar be quoted; nothing here needs the quotes.
fn unquote(value : String) -> String {
  for quote in ["\"", "'"] {
    if value.length() >= 2 && value.has_prefix(quote) && value.has_suffix(quote) {
      return value[1:value.length() - 1].to_owned()
    }
  }
  value
}
