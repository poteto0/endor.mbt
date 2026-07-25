///|
/// The empty-input digest is the single most-quoted keccak256 constant in
/// Ethereum: it is what `eth_getCode` hashes to for a non-contract account and
/// what an empty trie node holds.
test "hashes the empty input" {
  assert_eq(
    @crypto.keccak256(b""),
    b"\xc5\xd2\x46\x01\x86\xf7\x23\x3c\x92\x7e\x7d\xb2\xdc\xc7\x03\xc0\xe5\x00\xb6\x53\xca\x82\x27\x3b\x7b\xfa\xd8\x04\x5d\x85\xa4\x70",
  )
}

///|
/// Distinguishes keccak256 from SHA3-256: for `"abc"` the two differ, and only
/// this value is the one Ethereum uses.
test "hashes a short input" {
  assert_eq(
    @crypto.keccak256(b"abc"),
    b"\x4e\x03\x65\x7a\xea\x45\xa9\x4f\xc7\xd4\x7b\xa8\x26\xc8\xd6\x67\xc0\xd1\xe6\xe3\x3a\x64\xa0\x36\xec\x44\xf5\x8f\xa1\x2d\x6c\x45",
  )
}

///|
/// A string is hashed as its UTF-8 bytes, so the two entry points agree.
test "hashes a string as its utf-8 bytes" {
  assert_eq(@crypto.keccak256_string("abc"), @crypto.keccak256(b"abc"))
}

///|
/// Multi-byte characters must be encoded before hashing, not truncated: a
/// non-ASCII string is longer in bytes than in characters.
test "hashes non-ascii text" {
  assert_eq(
    @crypto.keccak256_string("こんにちは"),
    @crypto.keccak256(
      b"\xe3\x81\x93\xe3\x82\x93\xe3\x81\xab\xe3\x81\xa1\xe3\x81\xaf",
    ),
  )
}

///|
/// Real ERC-20 selectors — `keccak256(signature)[0..4]`. These are the values a
/// contract layer will put at the head of `data`, so they double as a check
/// that the digest is usable for #18.
test "derives erc-20 function selectors" {
  assert_eq(
    @crypto.keccak256_string("transfer(address,uint256)")[0:4],
    b"\xa9\x05\x9c\xbb"[:],
  )
  assert_eq(
    @crypto.keccak256_string("balanceOf(address)")[0:4],
    b"\x70\xa0\x82\x31"[:],
  )
  assert_eq(
    @crypto.keccak256_string("approve(address,uint256)")[0:4],
    b"\x09\x5e\xa7\xb3"[:],
  )
}

///|
/// The full hash of an event signature is a log's `topics[0]`.
test "derives an event topic" {
  assert_eq(
    @crypto.keccak256_string("Transfer(address,address,uint256)"),
    b"\xdd\xf2\x52\xad\x1b\xe2\xc8\x9b\x69\xc2\xb0\x68\xfc\x37\x8d\xaa\x95\x2b\xa7\xf1\x63\xc4\xa1\x16\x28\xf5\x5a\x4d\xf5\x23\xb3\xef",
  )
}

///|
/// Every input length yields a 32-byte digest, and lengths straddling the
/// 136-byte rate must not collide. The digests themselves are pinned against
/// published vectors in the whitebox test, which can reach the sponge directly.
test "produces a distinct 32-byte digest around the rate boundary" {
  let digests = []
  for len in [135, 136, 137] {
    let digest = @crypto.keccak256(Bytes::makei(len, _ => b'a'))
    assert_eq(digest.length(), 32)
    digests.push(digest)
  }
  assert_not_eq(digests[0], digests[1])
  assert_not_eq(digests[1], digests[2])
}
