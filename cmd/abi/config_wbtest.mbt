///|
test "parse_config: the shape the issue documents" {
  let config = parse_config(
    (
      #|version: v0.3.0
      #|abi:
      #|  in: ./abi
      #|  out: ./outputs
      #|
    ),
  )
  assert_eq(config.version, Some("v0.3.0"))
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
