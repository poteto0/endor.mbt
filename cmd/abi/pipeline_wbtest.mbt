///|
/// The whole CLI apart from `main`'s banner and exit code, driven against
/// scratch directories on a real filesystem.
///
/// It runs against the repository's own `fixtures/abi/erc20.abi` rather than
/// an inlined copy: the file the generator is pointed at in anger is a file on
/// disk, with whatever whitespace and ordering a compiler gave it, and reading
/// it here is what keeps the fixture and the tool from drifting apart.

///|
/// `moon test` runs with the module root as its working directory, so the
/// repository — and the fixtures in it — is one level up.
const FIXTURE = "../fixtures/abi/erc20.abi"

///|
/// Scratch lives under `_build/`, which is gitignored at every level, so a
/// test that fails half-way leaves nothing behind to commit by accident.
fn fresh(name : String) -> String raise {
  let dir = "_build/cli-test/\{name}"
  for parent in ["_build", "_build/cli-test", dir] {
    let _ = ensure_dir(parent)
  }
  // empty it: a rerun must not see the last run's output
  for entry in @fs.read_dir(dir) {
    if !@fs.is_dir(join(dir, entry)) {
      @fs.remove_file(join(dir, entry))
    }
  }
  dir
}

///|
/// An input directory holding the named files, each with the given content.
fn given(name : String, files : Array[(String, String)]) -> String raise {
  let dir = fresh(name)
  for file in files {
    @fs.write_string_to_file(join(dir, file.0), file.1)
  }
  dir
}

///|
test "the fixture ABI goes in and a MoonBit package comes out" {
  let abi = @fs.read_file_to_string(FIXTURE)
  let out = fresh("erc20-out")
  let config = {
    version: None,
    abi_in: given("erc20-in", [("erc20.abi", abi)]),
    abi_out: out,
  }
  assert_eq(run(config), 0)
  // named after the file, not after anything inside the ABI
  let code = @fs.read_file_to_string(join(out, "erc20.mbt"))
  assert_true(code.contains("pub struct Erc20 {"))
  assert_true(
    code.contains("pub async fn[P : @provider.Provider] Erc20::balance_of("),
  )
  assert_true(code.contains("Erc20::transfer_topic()"))
  // and the directory is a package, not just a loose file
  assert_true(
    @fs.read_file_to_string(join(out, "moon.pkg")).contains(
      "poteto0/endor/contract",
    ),
  )
}

///|
/// A second run over the same directories has to be a no-op apart from
/// rewriting the generated files — in particular it must not clobber a
/// `moon.pkg` the caller has since added imports to.
test "a rerun rewrites the generated files and leaves moon.pkg alone" {
  let abi = @fs.read_file_to_string(FIXTURE)
  let out = fresh("rerun-out")
  let config = {
    version: Some("v0.3.0"),
    abi_in: given("rerun-in", [("erc20.abi", abi)]),
    abi_out: out,
  }
  assert_eq(run(config), 0)
  let mine = @fs.read_file_to_string(join(out, "moon.pkg")) + "\n// mine\n"
  @fs.write_string_to_file(join(out, "moon.pkg"), mine)
  assert_eq(run(config), 0)
  assert_eq(@fs.read_file_to_string(join(out, "moon.pkg")), mine)
}

///|
/// The point of counting failures instead of raising: the one broken document
/// is reported, and every other file is still generated.
test "one unusable ABI does not cost the others" {
  let abi = @fs.read_file_to_string(FIXTURE)
  let out = fresh("mixed-out")
  let config = {
    version: None,
    abi_in: given("mixed-in", [
      ("erc20.abi", abi),
      ("truncated.abi", "[{ \"type\": \"function\""),
      // `9lives` cannot be a MoonBit type name, and the generator will not
      // invent one that is
      ("9lives.abi", "[]"),
    ]),
    abi_out: out,
  }
  assert_eq(run(config), 2)
  assert_true(@fs.path_exists(join(out, "erc20.mbt")))
  assert_false(@fs.path_exists(join(out, "truncated.mbt")))
  assert_false(@fs.path_exists(join(out, "9lives.mbt")))
}

///|
test "an input directory that is not there is reported, not raised" {
  assert_eq(
    run({
      version: None,
      abi_in: "_build/cli-test/nope",
      abi_out: "_build/cli-test/nope-out",
    }),
    1,
  )
}

///|
test "an empty input directory is nothing to do, not a failure" {
  let config = {
    version: None,
    abi_in: given("empty-in", []),
    abi_out: "_build/cli-test/empty-out",
  }
  assert_eq(run(config), 0)
  // and it stopped before creating an output directory it had nothing to fill
  assert_false(@fs.path_exists(join(config.abi_out, "moon.pkg")))
}

///|
/// A directory inside `abi.in` is somebody's own layout, not an ABI document.
test "a subdirectory of the input directory is stepped over" {
  let dir = given("nested-in", [("erc20.abi", @fs.read_file_to_string(FIXTURE))])
  let _ = ensure_dir(join(dir, "archive"))

  assert_eq(list_inputs(dir), ["erc20.abi"])
}

///|
test "the output directory is created when it is missing" {
  let out = "_build/cli-test/created-out"
  let config = {
    version: None,
    abi_in: given("created-in", [
      ("erc20.abi", @fs.read_file_to_string(FIXTURE)),
    ]),
    abi_out: out,
  }
  let _ = fresh("created-out")
  assert_eq(run(config), 0)
  assert_true(@fs.path_exists(join(out, "erc20.mbt")))
}

///|
test "the config is read off disk" {
  let dir = given("config-in", [
    ("endor.yaml", "version: v0.3.0\nabi:\n  in: ./abi\n  out: ./outputs\n"),
  ])
  let config = read_config(path=join(dir, "endor.yaml"))
  assert_eq(config.version, Some("v0.3.0"))
  assert_eq(config.abi_in, "./abi")
  assert_eq(config.abi_out, "./outputs")
}

///|
test "a config that is not there raises rather than defaulting" {
  try read_config(path="_build/cli-test/no-such.yaml") |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("expected a missing config to raise")
  }
}

///|
/// The `create_dir` failure that is really a failure.
///
/// The everyday one is not: on a second run the directory is already there, and
/// that raise has to be swallowed. What must not be swallowed is the path still
/// not existing afterwards — here because a *file* sits where the parent
/// directory would have to be, which no backend's `mkdir` can work around.
test "an output directory that cannot be created stops the run" {
  let dir = fresh("uncreatable")
  let blocked = join(dir, "file")
  @fs.write_string_to_file(blocked, "not a directory\n")
  let config = {
    version: None,
    abi_in: given("uncreatable-in", [
      ("erc20.abi", @fs.read_file_to_string(FIXTURE)),
    ]),
    abi_out: join(blocked, "out"),
  }
  assert_true(ensure_dir(config.abi_out) is Some(_))
  assert_eq(run(config), 1)
}

///|
/// Writing is reported per file, so a destination that exists but is not a
/// directory fails the file rather than the process — and the `moon.pkg` that
/// could not be written next to it is a warning, not another failure, since
/// there is nothing there for it to describe.
test "an output path that is not a directory fails the file it was for" {
  let dir = fresh("not-a-dir")
  let blocked = join(dir, "blocked")
  @fs.write_string_to_file(blocked, "not a directory\n")
  let config = {
    version: None,
    abi_in: given("not-a-dir-in", [
      ("erc20.abi", @fs.read_file_to_string(FIXTURE)),
    ]),
    abi_out: blocked,
  }
  assert_eq(run(config), 1)
}

///|
/// What the ABI holds and the generator would not translate is printed as it
/// happens, so a run that generated something incomplete says so on the
/// terminal rather than only in a comment at the bottom of a file nobody
/// opened yet.
test "a skipped member is counted and reported" {
  let out = fresh("skips-out")
  let config = {
    version: None,
    abi_in: given("skips-in", [
      (
        "vault.abi",
        (
          #|[
          #|  { "type": "function", "name": "holders", "stateMutability": "view",
          #|    "inputs": [], "outputs": [{ "name": "", "type": "address[]" }] },
          #|  { "type": "function", "name": "paused", "stateMutability": "view",
          #|    "inputs": [], "outputs": [{ "name": "", "type": "bool" }] }
          #|]
        ),
      ),
    ]),
    abi_out: out,
  }
  assert_eq(run(config), 0)
  let code = @fs.read_file_to_string(join(out, "vault.mbt"))
  assert_true(code.contains("Vault::paused("))
  assert_true(code.contains("// Not generated from this ABI:"))
  assert_false(code.contains("Vault::holders("))
}

///|
test "the banner warns before anything is generated" {
  // it takes no arguments and has no answer to assert on; what is being
  // pinned is that every run pays for it, including a run that succeeds
  banner()
}
