///|
test "parse_config: the shape the issue documents" {
  let config = parse_config(
    (
      #|version: v0.4.0
      #|abi:
      #|  in: ./abi
      #|  out: ./outputs
      #|
    ),
  )
  assert_eq(config.version, Some("v0.4.0"))
  assert_eq(config.abi_in, "./abi")
  assert_eq(config.abi_out, "./outputs")
}

///|
test "parse_config: comments, blank lines and CRLF are not content" {
  let config = parse_config(
    "# where the ABIs live\r\n\r\nabi:\r\n  in: abi\r\n  # and where they go\r\n  out: gen\r\n",
  )
  assert_eq(config.version, None)
  assert_eq(config.abi_in, "abi")
  assert_eq(config.abi_out, "gen")
}

///|
/// What `endor-cli init` writes, read by what `endor-cli abi` reads with.
///
/// The two halves of the same file live in different functions, and a default
/// config the reader rejects is a `init` that is worse than no `init` at all —
/// it puts a broken file where the caller will not think to look. So the
/// constant is parsed here rather than compared to a string.
test "the config `init` writes is a config `abi` can read" {
  let config = parse_config(default_config())
  assert_eq(config.version, Some("v\{VERSION}"))
  assert_eq(config.abi_in, "./abi")
  assert_eq(config.abi_out, "./outputs")
}

///|
/// The sample `endor-cli abi --help` prints, parsed as printed. A CLI whose own
/// documented config its own reader refuses is the failure this pins: the
/// comments are the reason the sample is worth reading, so they have to work.
test "parse_config: the sample in the usage text is a config that works" {
  let config = parse_config(
    (
      #|version: v0.4.0
      #|abi:
      #|  in: ./abi      # the directory of ABI documents to read
      #|  out: ./outputs # where to write MoonBit, created if missing
    ),
  )
  assert_eq(config.version, Some("v0.4.0"))
  assert_eq(config.abi_in, "./abi")
  assert_eq(config.abi_out, "./outputs")
}

///|
/// A `#` only opens a comment where YAML says it does. The distinction matters
/// in one direction only — a path silently truncated at a `#` is a directory
/// that is not there, reported as a name the caller never typed.
test "parse_config: a `#` inside a value is part of the value" {
  let config = parse_config(
    (
      #|abi:
      #|  in: ./abi#2
      #|  out: "./out # not a comment" # but this is
    ),
  )
  assert_eq(config.abi_in, "./abi#2")
  assert_eq(config.abi_out, "./out # not a comment")
}

///|
test "parse_config: a scalar may be quoted" {
  let config = parse_config(
    (
      #|abi:
      #|  in: "./abi"
      #|  out: './out'
    ),
  )
  assert_eq(config.abi_in, "./abi")
  assert_eq(config.abi_out, "./out")
}

///|
/// A key this CLI has never heard of is a newer `endor.yaml`, not a broken
/// one — so it is ignored rather than rejected.
test "parse_config: unknown keys are ignored" {
  let config = parse_config(
    (
      #|solidity: 0.8.24
      #|abi:
      #|  in: abi
      #|  out: gen
      #|  format: pretty
      #|other:
      #|  in: nowhere
    ),
  )
  assert_eq(config.abi_in, "abi")
  assert_eq(config.abi_out, "gen")
}

///|
test "parse_config: it has to say where to read and where to write" {
  try parse_config("abi:\n  out: gen\n") catch {
    e =>
      inspect(
        e,
        content="Incomplete(`abi.in` says nothing: there is no directory to read)",
      )
  } noraise {
    _ => fail("expected a missing `abi.in` to raise")
  }
  try parse_config("abi:\n  in: abi\n") catch {
    e =>
      inspect(
        e,
        content="Incomplete(`abi.out` says nothing: there is nowhere to write)",
      )
  } noraise {
    _ => fail("expected a missing `abi.out` to raise")
  }
  try parse_config("abi:\n  in:\n  out: gen\n") catch {
    e => assert_true(e is Incomplete(_))
  } noraise {
    _ => fail("expected an empty `abi.in` to raise")
  }
}

///|
/// The reader understands one shape and says so, rather than guessing at
/// YAML it was never written to handle.
test "parse_config: what it does not understand it refuses" {
  try parse_config("abi\n") catch {
    e => inspect(e, content="Malformed(`abi` is not `key: value`)")
  } noraise {
    _ => fail("expected a line with no colon to raise")
  }
  try parse_config("abi:\n  in: abi\n    deep: no\n  out: gen\n") catch {
    e =>
      inspect(
        e,
        content="Malformed(`deep: no` is indented 4 spaces; expected 0 or 2)",
      )
  } noraise {
    _ => fail("expected a third level to raise")
  }
}

///|
test "stem drops one extension and nothing else" {
  assert_eq(stem("erc20.abi"), "erc20")
  assert_eq(stem("my.token.abi.json"), "my.token.abi")
  assert_eq(stem("erc20"), "erc20")
  assert_eq(stem(".hidden"), ".hidden")
}

///|
test "join does not double a separator" {
  assert_eq(join("./abi", "erc20.abi"), "./abi/erc20.abi")
  assert_eq(join("./abi/", "erc20.abi"), "./abi/erc20.abi")
  assert_eq(join("", "erc20.abi"), "erc20.abi")
}
