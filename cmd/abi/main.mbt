///|
/// `endor-cli abi` — write one MoonBit contract preset per ABI document.
///
/// The command is deliberately argument-free: what it reads and where it
/// writes is in `endor.yaml`, which is checked in, so the generated files a
/// repository holds are reproducible by anyone who clones it rather than
/// dependent on the flags whoever ran it last happened to type.
///
/// ```sh
/// $ cat endor.yaml
/// version: v0.3.0
/// abi:
///   in: ./abi
///   out: ./outputs
/// $ endor-cli abi
/// erc20.abi -> ./outputs/erc20.mbt  (Erc20)
/// ```
///
/// Nothing here raises out of `main`. One unreadable ABI among twenty is worth
/// reporting and stepping over, not worth throwing away the other nineteen —
/// so failures are counted, printed as they happen, and answered for in the
/// exit code, which is what a build script actually reads.
fn main {
  banner()
  let config = read_config() catch {
    e => {
      println("error: \{CONFIG_FILE}: \{e}")
      return @sys.exit(1)
    }
  }
  if config.version is Some(version) {
    println("config: version \{version}")
  }
  if run(config) > 0 {
    @sys.exit(1)
  }
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
/// Split out of `main` so the whole pipeline can be driven from a test against
/// a scratch directory: `main` itself is only the banner, the config and the
/// exit code, none of which a test can observe.
fn run(config : Config) -> Int {
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
  write_package_config(config.abi_out)
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
/// `path` is a parameter only so a test can point at a scratch file; the CLI
/// never passes it, because a config found somewhere other than the current
/// directory would make the generated output depend on where the command was
/// run from.
fn read_config(path? : String = CONFIG_FILE) -> Config raise {
  parse_config(@fs.read_file_to_string(path))
}

///|
/// The files of a directory, sorted.
///
/// Sorted because the order `read_dir` answers in is the filesystem's, and a
/// generator whose output order depends on that produces a different summary
/// on a different machine for the same input. Directories are stepped over
/// rather than descended into: an `abi/` holding a subdirectory is far more
/// likely to be someone's own layout than a request to recurse.
fn list_inputs(dir : String) -> Array[String] raise {
  let files = []
  for entry in @fs.read_dir(dir) {
    if !@fs.is_dir(join(dir, entry)) {
      files.push(entry)
    }
  }
  files.sort()
  files
}

///|
/// Make sure a directory exists, answering with the reason it does not.
///
/// `create_dir` failing is the *normal* case on a second run, so the failure
/// that matters is not the raise — it is the path still not being there
/// afterwards.
fn ensure_dir(dir : String) -> String? {
  @fs.create_dir(dir) catch {
    e => if !@fs.path_exists(dir) { return Some(@debug.to_string(e)) }
  }
  None
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
  println(
    "\{input} -> \{out}  (\{name}, \{generated.members.length()} members)",
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
/// caller's file, it may import things the generator has no idea about, and
/// silently dropping those would be a worse failure than printing what is
/// missing and letting them add it.
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

///|
/// A file name without its extension: `erc20.abi` is `erc20`.
///
/// Only the last extension goes, and a name that is *all* extension (`.abi`)
/// keeps it — otherwise a dotfile would generate a struct with no name at all.
fn stem(file : String) -> String {
  match file.rev_split_once(".") {
    Some((name, _)) if name != "" => name.to_owned()
    _ => file
  }
}

///|
/// Two path segments, with exactly one separator between them.
///
/// The config's `in` and `out` are written by hand, so `./abi` and `./abi/`
/// both turn up and both have to mean the same directory.
fn join(dir : String, name : String) -> String {
  if dir == "" || dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}
