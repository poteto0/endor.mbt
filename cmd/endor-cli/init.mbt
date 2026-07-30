///|
/// `endor-cli init` — write the `endor.yaml` that `endor-cli abi` reads.
///
/// The file is four lines and `abi` refuses to run without it, so the first
/// thing anyone does with this CLI is type it out of the usage text. That is
/// the step a tool should take for them — and it is the step where the mistake
/// gets made, because the reader understands one shape and a hand-typed YAML
/// file can be wrong in ways that surface much later, as `abi` reading a
/// directory nobody meant.
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
/// Split from `handle_init` for the reason `generate_all` is split from
/// `handle_abi`: the command works on the directory it was run from, which a
/// test cannot be, so the directory is a parameter here and nowhere else. The
/// CLI passes `"."` and nothing else does.
///
/// It also creates the input directory the config names, so `init` leaves a
/// project where `abi` runs: an input directory that is not there is an error,
/// and an empty one is "nothing to do". The *output* directory is left alone —
/// `abi` creates that when it has something to put in it.
///
/// Nothing here overwrites. An `endor.yaml` that is already there is the
/// caller's, it may point somewhere this command would never have guessed, and
/// replacing it with the default is how `init` in the wrong directory becomes a
/// lost config rather than a message.
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
/// Read back off disk rather than taken from `default_config`, because on the
/// path where the config was already there it is the caller's file that
/// decides — and `init` telling someone to put ABIs in `./abi` when their own
/// config says `./contracts` would be worse than saying nothing at all. It is
/// also the only check that an `endor.yaml` already in place is one `abi` will
/// accept, which is worth knowing now rather than on the next run.
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
