///|
/// Sign `digest_digits` with `key_digits` and render the 65 wire bytes.
fn signed(key_digits : String, digest_digits : String) -> String raise {
  let key = @secp256k1.PrivateKey::from_bytes(
    @codec.bytes_of_digits(key_digits),
  )
  @codec.digits_of_bytes(
    key.sign(@codec.bytes_of_digits(digest_digits)).to_bytes(),
  )
}

///|
/// RFC 6979 §3.2 vectors for secp256k1 with SHA-256, as published in
/// `python-ecdsa`'s test suite. Each digest is the SHA-256 of the quoted
/// message; what they pin is the nonce, which `r` is a function of.
///
/// `s` is the low form. The vectors give the raw one, and EIP-2 wants the other
/// of the pair — `s_raw + s = N`, which the last test checks.
test "RFC 6979: key 1 over sha256(\"Satoshi Nakamoto\")" {
  assert_eq(
    signed(
      "0000000000000000000000000000000000000000000000000000000000000001", "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
    ),
    "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8" +
    "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5" +
    "01",
  )
}

///|
test "RFC 6979: key 1 over sha256(\"…tears in rain…\")" {
  assert_eq(
    signed(
      "0000000000000000000000000000000000000000000000000000000000000001", "7d1833f54854ac51659521afcd0ec6dca2ce2351429614bfa28a756b1b3c637f",
    ),
    "8600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b" +
    "547fe64427496db33bf66019dacbf0039c04199abb0122918601db38a72cfc21" +
    "00",
  )
}

///|
/// The largest key there is, which is also the one whose public point is `-G`.
test "RFC 6979: key N-1 over sha256(\"Satoshi Nakamoto\")" {
  assert_eq(
    signed(
      KEY_LAST,
      "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
    ),
    "fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0" +
    "6b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5" +
    "00",
  )
}

///|
test "RFC 6979: an ordinary key over sha256(\"Alan Turing\")" {
  assert_eq(
    signed(
      "f8b8af8ce3c7cca5e300d33939540c10d45ce001b8f252bfbc57ba0342904181", "4ba38d48a60f1b29e9eb726eaff08b2e83d8d81e031666fee50e85900d7dc1ef",
    ),
    "7063ae83e7f62bbb171798131b4a0564b956930092b33b07b395615d9ec7e15c" +
    "58dfcc1e00a35e1572f366ffe34ba0fc47db1e7189759b9fb233c5b05ab388ea" +
    "00",
  )
}

///|
/// go-ethereum's test key over `keccak256("foo")`, the digest its `TestSign`
/// signs — the same curve and nonce rule an Ethereum node would check.
test "the geth test key signs a keccak digest" {
  assert_eq(
    signed(
      TEST_PRIV,
      "41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d",
    ),
    "d155e94305af7e07dd8c32873e5c03cb95c9e05960ef85be9c07f671da58c737" +
    "18c19adc397a211aa9e87e519e2038c5a3b658618db335f74f800b8e0cfeef44" +
    "01",
  )
}

///|
/// A digest of zero is a scalar of zero, which the arithmetic takes like any
/// other — the one input where reading the digest could go wrong.
test "a zero digest still signs" {
  assert_eq(
    signed(
      TEST_PRIV,
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "7cf5985f34a10125c7e9a7e8d9939a2969b2bbb01c932329de8474e6d9374d66" +
    "38c37aacc3d498bf8ee7fad45e5d99ea6a754f567877704a1c2b7bf7539062cc" +
    "00",
  )
}

///|
/// Deterministic means deterministic: no randomness anywhere, so the same key
/// and digest give the same bytes every time. A signer that reached for entropy
/// would fail here and nowhere else.
test "signing is deterministic" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let digest = @codec.bytes_of_digits(
    "41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d",
  )
  assert_eq(key.sign(digest).to_bytes(), key.sign(digest).to_bytes())
}

///|
/// Different digests must not share a nonce — the failure that hands over the
/// private key outright. Equal `r` is what that looks like from outside, since
/// `r` is a function of the nonce alone.
test "a different digest gets a different nonce" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let one = key.sign(
    @codec.bytes_of_digits(
      "41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d",
    ),
  )
  let other = key.sign(
    @codec.bytes_of_digits(
      "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
    ),
  )
  assert_not_eq(one.r(), other.r())
}

///|
/// EIP-2: the high half of every pair is rejected by Ethereum, so nothing here
/// may produce one. Checked against the raw `s` the RFC 6979 vectors publish,
/// which is the high one for the first vector and the low one for the rest —
/// `s_low + s_raw = N` either way.
test "s is always the low half" {
  let n = @codec.bytes_of_digits(
    "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
  )
  let raw = [
    "dbbd3162d46e9f9bef7feb87c16dc13b4f6568a87f4e83f728e2443ba586675c", "ab8019bbd8b6924cc4099fe625340ffb1eaac34bf4477daa39d0835429094520",
  ]
  let digests = [
    "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e", "7d1833f54854ac51659521afcd0ec6dca2ce2351429614bfa28a756b1b3c637f",
  ]
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(KEY_ONE))
  for i, digest in digests {
    let s = key.sign(@codec.bytes_of_digits(digest)).s()
    // The pair sums to N, so the low one is whichever is under half of it.
    assert_eq(
      add_256(s, @codec.bytes_of_digits(raw[i])),
      @codec.digits_of_bytes(n),
    )
    assert_true(
      @codec.digits_of_bytes(s) <
      "8000000000000000000000000000000000000000000000000000000000000000",
    )
  }
}

///|
/// Add two 32-byte big-endian values, so the test can state `s_low + s_raw = N`
/// without reaching for a bignum the test package does not import.
fn add_256(a : Bytes, b : Bytes) -> String {
  let sum = Array::make(32, b'\x00')
  let mut carry = 0
  for i = 31; i >= 0; i = i - 1 {
    let total = a[i].to_int() + b[i].to_int() + carry
    sum[i] = (total & 0xff).to_byte()
    carry = total >> 8
  }
  @codec.digits_of_bytes(Bytes::from_array(sum))
}

///|
test "a digest that is not 32 bytes is refused" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  for
    wrong in [
      Bytes::new(0),
      @codec.bytes_of_digits("01"),
      Bytes::make(33, b'\x01'),
    ] {
    try key.sign(wrong) |> ignore catch {
      e => assert_eq(e, @secp256k1.InvalidLength("digest must be 256 bits"))
    } noraise {
      _ => fail("expected a length complaint for \{wrong}")
    }
  }
}
