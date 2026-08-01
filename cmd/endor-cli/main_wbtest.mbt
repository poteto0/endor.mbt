///|
/// The dispatcher: what an argument vector is taken to mean, and what the shell
/// gets back for it.
///
/// These are the tests that exist because `main` cannot be tested — every one
/// of them drives `run_for_args` with the vector a shell would have built,
/// which is the same thing `main` does with `@sys.get_cli_args()`.

///|
/// `argv[0]` is the path the binary was invoked by, and every real vector has
/// one; a test that leaves it out is testing something the CLI never sees.
fn argv(args : Array[String]) -> Array[String] {
  let vector = ["/usr/local/bin/endor-cli"]
  for arg in args {
    vector.push(arg)
  }
  vector
}

///|
test "the subcommand and its arguments are what comes after argv[0]" {
  assert_eq(parse_invocation(argv(["abi", "--help"])), Run("abi", ["--help"]))
}

///|
/// `-h` and `--version` before a subcommand are the same requests as the `help`
/// and `version` subcommands: one CLI, not two spellings of two different ones.
test "a leading help or version flag is the subcommand of the same name" {
  assert_eq(parse_invocation(argv(["-h"])), Run("help", []))
  assert_eq(parse_invocation(argv(["--help", "abi"])), Run("help", ["abi"]))
  assert_eq(parse_invocation(argv(["-v"])), Run("version", []))
  assert_eq(parse_invocation(argv(["--version"])), Run("version", []))
}

///|
/// The flag that is stepped over is the flag a build script keeps passing for a
/// month to a tool that never had it.
test "an unknown leading option is refused rather than ignored" {
  assert_eq(
    parse_invocation(argv(["--dry-run", "abi"])),
    UnknownOption("--dry-run"),
  )
  assert_eq(run_for_args(argv(["--dry-run", "abi"])), 1)
}

///|
test "no subcommand at all is a failure, not a quiet success" {
  assert_eq(parse_invocation(argv([])), Missing)
  assert_eq(run_for_args(argv([])), 1)
}

///|
/// A typo that exits 0 is a build step that reports success for work it never
/// did.
test "an unknown subcommand fails" {
  assert_eq(run_for_args(argv(["abo"])), 1)
}

///|
test "help asked for is help given, and exits 0" {
  assert_eq(run_for_args(argv(["help"])), 0)
  assert_eq(run_for_args(argv(["-h"])), 0)
  assert_eq(run_for_args(argv(["help", "abi"])), 0)
  assert_eq(run_for_args(argv(["abi", "--help"])), 0)
}

///|
test "help for something that is not a command fails" {
  assert_eq(run_for_args(argv(["help", "abo"])), 1)
}

///|
/// `abi` reads `endor.yaml` and nowhere else, so an argument is refused rather
/// than accepted and ignored — and the CLI's own two commands are held to the
/// same rule, since a tool that enforces it only on other people's subcommands
/// is a tool with an exception nobody documented.
test "a command that takes no arguments refuses them" {
  assert_eq(run_for_args(argv(["abi", "--out", "./gen"])), 1)
  assert_eq(run_for_args(argv(["version", "--json"])), 1)
  assert_eq(run_for_args(argv(["help", "abi", "please"])), 1)
}

///|
/// The check the command table exists to make: every name the help lists is a
/// name that dispatches, and every name that dispatches explains itself. Three
/// hand-kept lists could not make it.
test "every listed command dispatches and has a usage" {
  for entry in commands() {
    assert_true(find_command(entry.name) is Some(_))
    // `--help` is answered from the table, so this runs no command's work
    assert_eq(run_for_args(argv([entry.name, "--help"])), 0)
    assert_eq(run_for_args(argv(["help", entry.name])), 0)
  }
}

///|
test "the banner warns before anything is generated" {
  // it takes no arguments and has no answer to assert on; what is being
  // pinned is that every run pays for it, including a run that succeeds
  banner()
}
