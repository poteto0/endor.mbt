///|
/// A backend the end-to-end suite can run against: a real node, plus whatever
/// has to be in place before the SDK can reach it.
///
/// What differs between backends is not the calls but the *environment*. `run`
/// is the protocol every backend shares: skip when unconfigured, install once,
/// run the body in a task group.
pub(open) trait Backend {
  /// Named when the suite reports a skip.
  fn name(Self) -> String

  /// The JSON-RPC endpoint to run against, or `""` when this backend is not
  /// configured — which is what keeps a plain `moon test` hermetic.
  fn endpoint(Self) -> String

  /// Put the environment in place for `endpoint`. Called before every body and
  /// so must be idempotent — tests share one process, and one that installs
  /// into globals would otherwise clobber a test still running.
  fn install(Self, String) -> Unit
}

///|
/// Backends that have already announced a skip. Keyed by name rather than a
/// single flag: with two backends configured differently, one flag would let
/// the second skip in silence — and the whole point of announcing is that a
/// green run without a node cannot be mistaken for a green run against one.
let skip_reported : Array[String] = []

///|
/// Run `body` against `backend`, or skip when the backend is not configured.
///
/// An error from `body` reaches the test runner as-is: an `inspect` that fails
/// inside a body has to report its own location and diff, not the line that
/// caught it. So the tests themselves only catch where the error *is* the
/// assertion.
pub async fn[B : Backend] run(backend : B, body : async () -> Unit) -> Unit {
  let endpoint = backend.endpoint()
  if endpoint == "" {
    let name = backend.name()
    if !skip_reported.contains(name) {
      skip_reported.push(name)
      println(
        "e2e: skipped — no endpoint configured for \{name} (see `just e2e`)",
      )
    }
    return
  }
  backend.install(endpoint)
  @async.with_task_group(_ => body())
}
