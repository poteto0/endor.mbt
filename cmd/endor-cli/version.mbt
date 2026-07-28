///|
/// `endor-cli version` — say which build this is.
fn handle_version(args : Array[String]) -> Int {
  guard args is [] else {
    return refuse(
      "endor-cli version: unexpected argument `\{args[0]}`",
      print_usage,
    )
  }
  println("endor-cli \{VERSION}")
  0
}

///|
/// What it answers with.
///
/// Kept here rather than read from `moon.mod` because a compiled binary has no
/// `moon.mod` to read: whoever installs it gets a file, and the only version it
/// can tell them about is the one baked in when it was built. `just
/// release-check <tag>` asserts this agrees with `cmd/moon.mod` and with the
/// SDK it pins, so the three cannot drift apart unnoticed.
const VERSION = "0.3.0"
