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
/// Kept here rather than read from `moon.mod` because a compiled binary has none
/// to read. `just release-check <tag>` asserts this agrees with `cmd/moon.mod`
/// and with the SDK it pins.
const VERSION = "0.8.0"
