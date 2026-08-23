///|
/// `endor-cli abi` — write one MoonBit contract preset per ABI document.
///
/// Deliberately argument-free: what it reads and where it writes is in the
/// checked-in `endor.yaml`, so an argument that would change the output is
/// refused rather than ignored. Nothing here raises — one unreadable ABI among
/// twenty is counted, printed, and answered for in the exit code.
fn handle_abi(args : Array[String]) -> Int {
  guard args is [] else {
    return refuse(
      "endor-cli abi: unexpected argument `\{args[0]}`",
      print_abi_usage,
    )
  }
  banner()
  let config = read_config() catch {
    e => {
      println("error: \{CONFIG_FILE}: \{e}")
      return 1
    }
  }
  if config.version is Some(version) {
    println("config: version \{version}")
  }
  if generate_all(config) > 0 {
    1
  } else {
    0
  }
}

///|
fn print_abi_usage() -> Unit {
  println(
    (
      #|usage: endor-cli abi
      #|
      #|Write one MoonBit contract preset per ABI document. EXPERIMENTAL.
      #|
      #|Takes no arguments: what it reads and where it writes is `endor.yaml` in
      #|the directory it is run from, so the generated files a repository holds
      #|are reproducible by anyone who clones it.
      #|
      #|version: v0.4.0
      #|abi:
      #|  in: ./abi      # the directory of ABI documents to read
      #|  out: ./outputs # where to write MoonBit, created if missing
      #|
      #|One input becomes one output named after it — `erc20.abi` generates
      #|`erc20.mbt` holding `pub struct Erc20` — plus a `moon.pkg` alongside if
      #|there is not one already. An existing `moon.pkg` is never touched, only
      #|reported on.
      #|
      #|An input may be the JSON array of ABI members, or a compiler artifact
      #|holding one — `solc --combined-json abi,bin`, solc's standard JSON, a
      #|Foundry or a Hardhat artifact. An artifact also carries the creation
      #|code, and then the generated struct gets a `deploy` as well: the file
      #|can put the contract on chain, not only call one already there.
      #|
      #|Exits non-zero if any document could not be generated; the ones that
      #|could are still written.
    ),
  )
}

///|
/// The warning every run carries.
///
/// It is printed unconditionally, including on a run that generates cleanly,
/// because a clean run is exactly the one that invites the mistake: no skipped
/// members does not mean the ABI was fully understood, only that nothing in it
/// tripped a check this generator knows how to make.
fn banner() -> Unit {
  println("endor-cli abi — EXPERIMENTAL")
  println(
    "  Generated code is a starting point, not an audited binding. Read the\n" +
    "  file before you ship it: what could not be generated safely was left\n" +
    "  out, and is listed in a comment at the bottom of each file.",
  )
  println("")
}

///|
/// Generate every file the config asks for, answering with how many failed.
///
/// Split out of `handle_abi` so the whole pipeline can be driven from a test
/// against a scratch directory: what `handle_abi` adds around it is the banner,
/// the config and the exit code, none of which a test can observe.
fn generate_all(config : Config) -> Int {
  let inputs = list_inputs(config.abi_in) catch {
    e => {
      println("error: cannot read \{config.abi_in}: \{@debug.to_string(e)}")
      return 1
    }
  }
  if inputs.is_empty() {
    println("nothing to do: \{config.abi_in} holds no files")
    return 0
  }
  guard ensure_dir(config.abi_out) is None else {
    println("error: cannot create \{config.abi_out}")
    return 1
  }
  let mut failed = 0
  let mut skipped = 0
  for input in inputs {
    match generate_one(input, config) {
      Ok(count) => skipped += count
      Err(message) => {
        println("error: \{message}")
        failed += 1
      }
    }
  }
  // a run where every document failed wrote no source, and a `moon.pkg` on its
  // own is a package with nothing in it
  if failed < inputs.length() {
    write_package_config(config.abi_out)
  }
  println("")
  println(
    "generated \{inputs.length() - failed} of \{inputs.length()} into \{config.abi_out}" +
    "; \{skipped} ABI member(s) skipped, \{failed} file(s) failed",
  )
  failed
}

///|
/// Where the config is read from, relative to the directory the CLI runs in.
const CONFIG_FILE = "endor.yaml"

///|
/// Read and parse the config.
///
/// `path` is a parameter only so a test can point at a scratch file. The `raise`
/// is untyped because two unrelated errors reach it — `@fs`'s and
/// `ConfigError` — and the only caller prints both the same way.
fn read_config(path? : String = CONFIG_FILE) -> Config raise {
  parse_config(@fs.read_file_to_string(path))
}

///|
/// Generate one file, answering with how many ABI members it left out.
///
/// The struct's name comes from the input's file name and nothing else —
/// `erc20.abi` gives `Erc20` — so renaming the input is how a caller renames
/// the generated type, and two ABIs whose names differ only in punctuation are
/// a collision the caller resolves by naming their files apart.
fn generate_one(input : String, config : Config) -> Result[Int, String] {
  let from = join(config.abi_in, input)
  let source = @fs.read_file_to_string(from) catch {
    e => return Err("cannot read \{from}: \{@debug.to_string(e)}")
  }
  let stem = stem(input)
  let name = @codegen.pascal_case(stem)
  let generated = @codegen.generate(name, source) catch {
    e => return Err("\{input}: \{e}")
  }
  let out = join(config.abi_out, @codegen.snake_case(stem) + ".mbt")
  @fs.write_string_to_file(out, generated.code) catch {
    e => return Err("cannot write \{out}: \{@debug.to_string(e)}")
  }
  // whether the document carried creation code is the one thing a caller
  // cannot tell from the input's name
  let deploys = if generated.deploys { ", deployable" } else { "" }
  println(
    "\{input} -> \{out}  (\{name}, \{generated.members.length()} members\{deploys})",
  )
  for line in generated.skipped {
    println("  skipped \{line}")
  }
  Ok(generated.skipped.length())
}

///|
/// Put a `moon.pkg` next to the generated files, so what was written is a
/// package that compiles rather than source nobody can build.
///
/// An existing one is never overwritten and never merged into: it is the
/// caller's file, and it may import things the generator has no idea about.
fn write_package_config(dir : String) -> Unit {
  let path = join(dir, "moon.pkg")
  if @fs.path_exists(path) {
    println("")
    println("\{path} exists and was left alone; it has to import:")
    println(@codegen.moon_pkg())
    return
  }
  try @fs.write_string_to_file(path, @codegen.moon_pkg()) catch {
    e => println("warning: cannot write \{path}: \{@debug.to_string(e)}")
  } noraise {
    _ => println("wrote \{path}")
  }
}
