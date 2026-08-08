///|
/// The claim `hashes` makes, and the one thing a caller cannot observe of it: a
/// memoized pure function answers what an unmemoized one would. A delta, since
/// every other test hashes signatures of its own.
test "a signature is hashed once, for both of its cuts" {
  let before = hashes.length()
  let sig = "onceOnly(uint256,bytes)"
  let four_bytes = selector(sig)
  assert_eq(four_bytes, selector(sig))
  assert_eq(hashes.length(), before + 1)
  // the topic comes out of the entry the selector made, not a second one
  assert_true(event_topic(sig).to_string().has_prefix(four_bytes.to_string()))
  assert_eq(hashes.length(), before + 1)
}
