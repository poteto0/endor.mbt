///|
/// Reading directories and naming files: what `abi` needs of the filesystem,
/// kept apart from what it needs of an ABI.
///
/// It is a file rather than a section of `abi.mbt` because none of it is about
/// ABIs — so the next subcommand that has to walk a directory has somewhere
/// obvious to look before writing its own.

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
