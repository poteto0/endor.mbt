///|
/// A benchmark body cannot raise, and these two keys are in range by
/// construction, so the catch is unreachable and costs nothing next to the 256
/// doublings it wraps.
fn reading(digits : String) -> () -> Unit {
  let bytes = @codec.bytes_of_digits(digits)
  fn() {
    try @secp256k1.PrivateKey::from_bytes(bytes) |> ignore catch {
      _ => ()
    }
  }
}

///|
/// Reading a key is one scalar multiplication, which is the whole cost. The two
/// scalars are the cheap end and the dear end of the double-and-add: `1` sets
/// one bit, `N - 1` sets nearly all of them.
test "bench: PrivateKey::from_bytes" (b : @bench.T) {
  b.bench(name="one bit", reading(KEY_ONE))
  b.bench(name="every bit", reading(KEY_LAST))
}
