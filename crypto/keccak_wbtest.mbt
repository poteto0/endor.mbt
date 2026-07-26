///|
/// SHA3-256's domain-separation byte. Only used to test with — see below.
const SHA3_PAD : Byte = 0x06

///|
/// keccak256 has no reference implementation in any standard library, because
/// what every standard library ships is SHA3-256 — the same permutation, the
/// same rate, the same sponge, differing only in the byte `pad10*1` appends.
/// Swapping that one byte therefore turns this code into SHA3-256 and lets the
/// permutation, the absorb loop and the rate-boundary padding all be checked
/// against published vectors instead of against itself.
///
/// The lengths are chosen around the 136-byte rate: 135 puts the pad byte and
/// the closing high bit on the same byte, 136 forces a block that is nothing
/// but padding, 137 opens a fresh tail, 271 repeats that boundary a block
/// later, and 1000 spans several blocks.
test "matches sha3-256 vectors when given sha3's pad byte" {
  let vectors : Array[(Bytes, Bytes)] = [
    (
      b"", b"\xa7\xff\xc6\xf8\xbf\x1e\xd7\x66\x51\xc1\x47\x56\xa0\x61\xd6\x62\xf5\x80\xff\x4d\xe4\x3b\x49\xfa\x82\xd8\x0a\x4b\x80\xf8\x43\x4a",
    ),
    (
      b"abc", b"\x3a\x98\x5d\xa7\x4f\xe2\x25\xb2\x04\x5c\x17\x2d\x6b\xd3\x90\xbd\x85\x5f\x08\x6e\x3e\x9d\x52\x5b\x46\xbf\xe2\x45\x11\x43\x15\x32",
    ),
    (
      Bytes::makei(135, _ => b'a'),
      b"\x80\x94\xbb\x53\xc4\x4c\xfb\x1e\x67\xb7\xc3\x04\x47\xf9\xa1\xc3\x36\x96\xd2\x46\x3e\xcc\x1d\x9c\x92\x53\x89\x13\x39\x28\x43\xc9",
    ),
    (
      Bytes::makei(136, _ => b'a'),
      b"\x3f\xc5\x55\x9f\x14\xdb\x8e\x45\x3a\x0a\x30\x91\xed\xbd\x2b\xc2\x5e\x11\x52\x8d\x81\xc6\x6f\xa5\x70\xa4\xef\xdc\xc2\x69\x5e\xe1",
    ),
    (
      Bytes::makei(137, _ => b'a'),
      b"\xf8\xd6\x84\x6c\xed\xd2\xcc\xfa\xdf\x15\xc5\x87\x9e\xf9\x5a\xf7\x24\xd7\x99\xee\xd7\x39\x1f\xb1\xc9\x1f\x95\x34\x4e\x73\x86\x14",
    ),
    (
      Bytes::makei(271, _ => b'a'),
      b"\xe7\x9e\x5c\x6f\xef\x1b\xb5\xfd\xea\x27\x17\xca\x27\xe8\x83\x99\xe9\xb6\x46\x99\xd1\xb3\xeb\x8e\x30\xf3\x14\xfa\x05\x52\x14\xe8",
    ),
    (
      Bytes::makei(1000, _ => b'a'),
      b"\x8f\x39\x34\xe6\xf7\xa1\x56\x98\xfe\x0f\x39\x6b\x95\xd8\xc4\x44\x09\x29\xa8\xfa\x6e\xae\x14\x01\x71\xc0\x68\xb4\x54\x9f\xbf\x81",
    ),
  ]
  for vector in vectors {
    let (input, expected) = vector
    assert_eq(sponge(input, SHA3_PAD), expected)
  }
}

///|
/// The distinction the whole file rests on: one byte of padding, and the two
/// digests share nothing.
test "keccak256 and sha3-256 disagree on the same input" {
  assert_not_eq(sponge(b"abc", KECCAK_PAD), sponge(b"abc", SHA3_PAD))
}
