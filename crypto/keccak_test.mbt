///|
/// The empty-input digest is the single most-quoted keccak256 constant in
/// Ethereum: it is what `eth_getCode` hashes to for a non-contract account and
/// what an empty trie node holds.
test "hashes the empty input" {
  inspect(
    @crypto.keccak256(b""),
    content=(
      #|b"\xc5\xd2F\x01\x86\xf7#<\x92~}\xb2\xdc\xc7\x03\xc0\xe5\x00\xb6S\xca\x82';{\xfa\xd8\x04]\x85\xa4p"
    ),
  )
}

///|
/// Distinguishes keccak256 from SHA3-256: for `"abc"` the two differ, and only
/// this value is the one Ethereum uses.
test "hashes a short input" {
  inspect(
    @crypto.keccak256(b"abc"),
    content=(
      #|b"N\x03ez\xeaE\xa9O\xc7\xd4{\xa8&\xc8\xd6g\xc0\xd1\xe6\xe3:d\xa06\xecD\xf5\x8f\xa1-lE"
    ),
  )
}

///|
/// A string is hashed as its UTF-8 bytes, so the two entry points agree.
test "hashes a string as its utf-8 bytes" {
  inspect(
    @crypto.keccak256_string("abc"),
    content=(
      #|b"N\x03ez\xeaE\xa9O\xc7\xd4{\xa8&\xc8\xd6g\xc0\xd1\xe6\xe3:d\xa06\xecD\xf5\x8f\xa1-lE"
    ),
  )
}

///|
/// Multi-byte characters must be encoded before hashing, not truncated: a
/// non-ASCII string is longer in bytes than in characters.
test "hashes non-ascii text" {
  inspect(
    @crypto.keccak256_string("こんにちは"),
    content=(
      #|b"\xf8RE\x81\x00\xefF\xb3H\xa8\x88\x8d\xec\x19c\xdcX\xef\x1e\xff6M\xaf\x05\xb1\xb6+-|n\x22W"
    ),
  )
}

///|
/// Real ERC-20 selectors — `keccak256(signature)[0..4]`. These are the values a
/// contract layer will put at the head of `data`, so they double as a check
/// that the digest is usable for #18.
test "derives erc-20 function selectors" {
  inspect(
    @crypto.keccak256_string("transfer(address,uint256)")[0:4],
    content=(
      #|b"\xa9\x05\x9c\xbb"
    ),
  )
  inspect(
    @crypto.keccak256_string("balanceOf(address)")[0:4],
    content=(
      #|b"p\xa0\x821"
    ),
  )
  inspect(
    @crypto.keccak256_string("approve(address,uint256)")[0:4],
    content=(
      #|b"\x09^\xa7\xb3"
    ),
  )
}

///|
/// The full hash of an event signature is a log's `topics[0]`.
test "derives an event topic" {
  inspect(
    @crypto.keccak256_string("Transfer(address,address,uint256)"),
    content=(
      #|b"\xdd\xf2R\xad\x1b\xe2\xc8\x9bi\xc2\xb0h\xfc7\x8d\xaa\x95+\xa7\xf1c\xc4\xa1\x16(\xf5ZM\xf5#\xb3\xef"
    ),
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
