///|
/// One subcommand: what it is called, where it belongs in the help, what it
/// does in a line, how to run it, and how it explains itself.
struct Command {
  name : String
  /// The heading it is listed under in `endor-cli help`.
  section : String
  blurb : String
  run : (Array[String]) -> Int
  usage : () -> Unit
}

///|
/// Every subcommand there is.
///
/// One table, read three ways: `dispatch` runs from it, `handle_help` explains
/// from it, `print_usage` is rendered from it. Order is the order the help
/// prints in. A `fn` rather than a `let` because a top-level value holding these
/// entries is a definition cycle MoonBit refuses.
fn commands() -> Array[Command] {
  [
    {
      name: "init",
      section: "generate code",
      blurb: "Write the `endor.yaml` that `abi` reads",
      run: handle_init,
      usage: print_init_usage,
    },
    {
      name: "abi",
      section: "generate code",
      blurb: "Write a MoonBit contract preset per ABI document (EXPERIMENTAL)",
      run: handle_abi,
      usage: print_abi_usage,
    },
    {
      name: "help",
      section: "about",
      blurb: "Show this help, or `help <command>` for one command",
      run: handle_help,
      usage: print_usage,
    },
    {
      name: "version",
      section: "about",
      blurb: "Print the version of this binary",
      run: handle_version,
      usage: print_usage,
    },
  ]
}

///|
fn find_command(name : String) -> Command? {
  let table = commands()
  table.search_by(entry => entry.name == name).map(at => table[at])
}

///|
/// Run one subcommand, answering with its exit code.
///
/// An unknown subcommand is a failure rather than a no-op — a typo'd command
/// that exits 0 is a build script that reports success for work it never did.
fn dispatch(command : String, args : Array[String]) -> Int {
  guard find_command(command) is Some(entry) else {
    return refuse("endor-cli: unknown subcommand `\{command}`", print_usage)
  }
  // `help abi` and `abi --help` are the same question, answered here so no
  // subcommand can forget `--help`
  if args is ["-h" | "--help", ..] {
    (entry.usage)()
    return 0
  }
  (entry.run)(args)
}

///|
/// `endor-cli help [<subcommand>]`.
///
/// Help asked for is help printed on stdout and an exit code of 0: it is what
/// the caller wanted, not a failure. Help printed *because* of a mistake is
/// reported by whoever caught the mistake, and exits non-zero there.
fn handle_help(args : Array[String]) -> Int {
  match args {
    [] => {
      print_usage()
      0
    }
    [topic] =>
      match find_command(topic) {
        Some(entry) => {
          (entry.usage)()
          0
        }
        None => refuse("endor-cli: no help topic for `\{topic}`", print_usage)
      }
    [_, extra, ..] =>
      refuse("endor-cli help: unexpected argument `\{extra}`", print_usage)
  }
}

///|
/// What `endor-cli` says when it is asked what it can do.
///
/// Rendered from `commands()` rather than written out, so a subcommand cannot
/// exist without being listed and cannot be listed without existing.
fn print_usage() -> Unit {
  println("usage: endor-cli [-h | --help] [-v | --version] <command> [<args>]")
  println("")
  println("The command line tools for poteto0/endor.")
  let mut section = ""
  for entry in commands() {
    if entry.section != section {
      section = entry.section
      println("")
      println(section)
    }
    println("   \{entry.name.pad_end(NAME_COLUMN, ' ')} \{entry.blurb}")
  }
  println("")
  println("See `endor-cli help <command>` for what a command reads and writes.")
}

///|
/// How wide the name column of the help is. Nothing enforces that a name fits
/// it: a longer one pushes its own line out rather than being cut short, since
/// a truncated command name is a command nobody can type.
const NAME_COLUMN = 10

///|
/// Say what went wrong, show what would have been right, and fail.
///
/// Every refusal in this CLI has the same shape, so changing it is one edit. The
/// stream is stdout, which is not where a diagnostic belongs, because neither
/// `moonbitlang/core` nor `moonbitlang/x` exposes stderr; the exit code carries
/// the signal in the meantime.
fn refuse(message : String, usage : () -> Unit) -> Int {
  println(message)
  println("")
  usage()
  1
}
