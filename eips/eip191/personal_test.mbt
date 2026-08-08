///|
/// The vector every other library agrees on for `"hello world"` — the check
/// that the prefix, the decimal length and the UTF-8 are all what a wallet
/// would have hashed, and not merely self-consistent.
test "hash_message matches the published personal_sign digest" {
  inspect(
    @eip191.hash_message("hello world"),
    content="0xd9eba16ed0ecae432b71fe008c98cc872bb4cc214d3220a36f365326cf807d68",
  )
}

///|
/// Text and its UTF-8 are the same message.
test "hash_message and hash_bytes agree on the same bytes" {
  inspect(
    @eip191.hash_bytes(b"hello world") == @eip191.hash_message("hello world"),
    content="true",
  )
}

///|
/// The length is what keeps concatenation from collapsing: `"ab" ‖ "c"` and
/// `"abc"` are the same bytes, and must not be the same digest as `"ab"`
/// followed by anything.
test "the length prefix separates messages that concatenate" {
  let abc = @eip191.hash_message("abc")
  let ab = @eip191.hash_message("ab")
  inspect(abc == ab, content="false")
  inspect(abc.byte_length(), content="32")
}

///|
/// The length is counted in bytes, not characters — a multi-byte character
/// makes the prefix disagree with `String::length()`.
test "hash_message counts UTF-8 bytes" {
  inspect(
    @eip191.hash_message("あ") == @eip191.hash_bytes(b"\xe3\x81\x82"),
    content="true",
  )
}

///|
/// An empty message still has a digest — `len` is `0`, and the prefix alone is
/// hashed.
test "hash_message accepts an empty message" {
  inspect(@eip191.hash_message("").byte_length(), content="32")
}
