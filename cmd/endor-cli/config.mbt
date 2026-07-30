///|
/// Where `endor-cli abi` reads ABI documents from and writes MoonBit to.
///
/// This is `endor.yaml`, and it is the whole of it:
///
/// ```yaml
/// version: v0.4.0
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
    // the indent is the one thing that needs the line as written; everything
    // after it is about the content, so the content is trimmed once
    let indent = line.length() - line.trim_start(chars=" ").length()
    let text = line.trim().to_owned()
    if text.is_empty() || text.has_prefix("#") {
      continue
    }
    guard text.split_once(":") is Some((key, rest)) else {
      raise Malformed("`\{text}` is not `key: value`")
    }
    let key = key.trim().to_owned()
    let value = scalar(rest.trim().to_owned())
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
          "`\{text}` is indented \{indent} spaces; expected 0 or 2",
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
/// What a `key:` is actually worth: the scalar, with its quotes and its
/// trailing comment gone.
///
/// Both in one pass, because they are one question. Where the quote ends is
/// where the comment may begin — `"./a # b"` is a path and `"./a" # b` is a
/// path with a comment after it — so finding the closing quote twice, once to
/// know what to strip and once to know what to unwrap, is finding out the same
/// thing twice.
///
/// The `#` has to be preceded by a space to open a comment, which is what
/// keeps `./abi#2` whole. YAML draws the same line, and a directory with a `#`
/// in its name is likelier than a caller who wanted an empty value. An
/// unterminated quote is left exactly as written: it is not a scalar this
/// reader understands, and the caller seeing back what they typed is the
/// clearest thing it can do about that.
fn scalar(value : String) -> String {
  guard value.has_prefix("\"") || value.has_prefix("'") else {
    return match value.find(" #") {
      Some(at) => value[:at].trim_end(chars=" ").to_owned()
      None => value
    }
  }
  guard value[1:].to_owned().find(value[:1].to_owned()) is Some(close) else {
    return value
  }
  value[1:close + 1].to_owned()
}
