///|
/// `endor-cli init` — write the `endor.yaml` that `endor-cli abi` reads.
///
/// The file is four lines and `abi` refuses to run without it, so the first
/// thing anyone does with this CLI is type it out of the usage text. That is
/// also where the mistake gets made, and it surfaces much later.
fn handle_init(args : Array[String]) -> Int {
  guard args is [] else {
    return refuse(
      "endor-cli init: unexpected argument `\{args[0]}`",
      print_init_usage,
    )
  }
  init_in(".")
}

///|
/// Write the config into a directory, answering with an exit code.
///
/// The directory is a parameter here and nowhere else, so a test can point
/// somewhere the CLI never does. It also creates the input directory the config
/// names, so `init` leaves a project where `abi` runs. Nothing here overwrites:
/// an `endor.yaml` already there is the caller's.
fn init_in(dir : String) -> Int {
  let path = join(dir, CONFIG_FILE)
  if @fs.path_exists(path) {
    println("\{path} is already here; left alone")
    return ensure_inputs(dir, path)
  }
  @fs.write_string_to_file(path, default_config()) catch {
    e => {
      println("error: cannot write \{path}: \{@debug.to_string(e)}")
      return 1
    }
  }
  println("wrote \{path}")
  println("")
  println(default_config())
  ensure_inputs(dir, path)
}

///|
/// Create the directory the config points at, and say what to do next.
///
/// Read back off disk rather than taken from `default_config`, because where the
/// config was already there it is the caller's file that decides. It is also the
/// only check that an `endor.yaml` in place is one `abi` will accept.
fn ensure_inputs(dir : String, path : String) -> Int {
  let config = read_config(path~) catch {
    e => {
      println("error: \{path}: \{e}")
      return 1
    }
  }
  let inputs = join(dir, config.abi_in)
  guard ensure_dir(inputs) is None else {
    println("error: cannot create \{inputs}")
    return 1
  }
  println("put ABI documents in \{config.abi_in}, then run `endor-cli abi`")
  0
}

///|
fn print_init_usage() -> Unit {
  println(
    (
      #|usage: endor-cli init
      #|
      #|Write the `endor.yaml` that `endor-cli abi` reads, and create the input
      #|directory it names.
      #|
      #|Takes no arguments: it writes the default config in the directory it is
      #|run from. An `endor.yaml` that is already there is never overwritten —
      #|it is four lines, edit it by hand.
      #|
      #|Exits non-zero if the file or the directory could not be written, or if
      #|an `endor.yaml` that was already there does not parse.
    ),
  )
}
