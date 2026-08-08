///|
/// `endor-cli` — the command line tools that ship alongside `poteto0/endor`.
///
/// The binary is a dispatcher and nothing else: it works out which subcommand
/// was asked for, hands the rest of the arguments to that subcommand's handler,
/// and turns what comes back into an exit code. Every subcommand lives in its
/// own file (`abi.mbt`), answers with an `Int`, and prints its own diagnostics —
/// so adding one is adding a file and an entry to `commands()` in
/// `dispatch.mbt`, and none of it touches `main`.
///
/// ```sh
/// $ endor-cli abi
/// $ endor-cli help abi
/// $ endor-cli --version
/// ```
fn main {
  let code = run_for_args(@env.args())
  // `@sys.exit` is a process-level jump; the happy path just returns
  if code != 0 {
    @sys.exit(code)
  }
}

///|
/// The whole CLI, from an argument vector to an exit code.
///
/// Split from `main` for the reason every entry point should be: `main` can
/// only be observed by running a process, and this can be called from a test.
/// Nothing below it calls `@sys.exit` either — a handler that reports failure
/// by returning it can be tested for having reported it.
fn run_for_args(argv : Array[String]) -> Int {
  match parse_invocation(argv) {
    Run(command, args) => dispatch(command, args)
    Missing => refuse("endor-cli: no subcommand", print_usage)
    UnknownOption(option) =>
      refuse("endor-cli: unknown option `\{option}`", print_usage)
  }
}

///|
/// What an argument vector turned out to be asking for.
enum Invocation {
  /// A subcommand, and everything after it.
  Run(String, Array[String])
  /// Nothing was asked for: `endor-cli` on its own.
  Missing
  /// An option before the subcommand that this CLI does not know.
  UnknownOption(String)
} derive(Eq, Debug)

///|
/// Work out what the argument vector is asking for, without acting on it.
///
/// `argv[0]` is the path the binary was invoked by and is skipped. Options
/// before the subcommand are handled here rather than in the handlers, because
/// they are answers the CLI can give without knowing which subcommand it is
/// about to run — and `--version` on a machine where `abi` would fail still has
/// to print the version.
///
/// An unrecognised leading option is refused rather than stepped over. A flag
/// silently ignored is the failure mode where somebody's build script has been
/// passing `--dry-run` for a month to a tool that never had one.
fn parse_invocation(argv : Array[String]) -> Invocation {
  for i in 1..<argv.length() {
    match argv[i] {
      "-h" | "--help" => return Run("help", argv[i + 1:].to_owned())
      "-v" | "--version" => return Run("version", [])
      option if option.has_prefix("-") => return UnknownOption(option)
      command => return Run(command, argv[i + 1:].to_owned())
    }
  }
  Missing
}
