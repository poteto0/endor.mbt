///|
/// `keccak256("foo")`, the digest geth's `TestSign` signs.
const FOO_DIGEST = "41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d"

///|
/// Recover the key that signed `digest_digits` from the 65 wire bytes
/// `signature_digits`, and render it as digits.
fn recovered(signature_digits : String, digest_digits : String) -> String raise {
  let signature = @secp256k1.Signature::from_bytes(
    @codec.bytes_of_digits(signature_digits),
  )
  @codec.digits_of_bytes(
    signature.recover(@codec.bytes_of_digits(digest_digits)),
  )
}

///|
/// The public key of `key_digits`, as digits.
fn public_key_of(key_digits : String) -> String raise {
  @codec.digits_of_bytes(
    @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(key_digits)).public_key(),
  )
}

///|
/// Recovery against a signature nobody here produced: each row is a signature
/// and the digest it was made over, published by somebody else, and the key it
/// has to land back on. Nothing self-consistent about this package can arrange
/// any of them.
test "published signatures recover their published keys" {
  let vectors = [
    // go-ethereum's `TestSign`: its test key over `keccak256("foo")`. The 65
    // bytes are geth's, pinned in `sign_test.mbt` as what signing produces.
    (
      "d155e94305af7e07dd8c32873e5c03cb95c9e05960ef85be9c07f671da58c737" +
      "18c19adc397a211aa9e87e519e2038c5a3b658618db335f74f800b8e0cfeef44" +
      "01",
      FOO_DIGEST,
      TEST_PRIV,
    ),
    // RFC 6979 §3.2, key 1 over `sha256("Satoshi Nakamoto")` — the same vector
    // `sign_test.mbt` signs. The signature is the RFC's, so recovering it is a
    // check against the document rather than against the signer.
    (
      "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8" +
      "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5" +
      "01",
      "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
      KEY_ONE,
    ),
    // The largest key there is, whose public point is `-G`: RFC 6979 again,
    // over the same message.
    (
      "fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0" +
      "6b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5" +
      "00",
      "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
      KEY_LAST,
    ),
  ]
  for vector in vectors {
    let (signature_digits, digest_digits, key_digits) = vector
    assert_eq(
      recovered(signature_digits, digest_digits),
      public_key_of(key_digits),
    )
  }
}

///|
/// Sign, put it on the wire, read it back, recover: the whole path, over the
/// two ends of the key range and an ordinary key, and over a zero digest —
/// the input where reading the digest as a scalar could go wrong.
test "sign, serialise, parse and recover is the identity" {
  let digests = [
    "0000000000000000000000000000000000000000000000000000000000000000",
    FOO_DIGEST,
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  ]
  for key_digits in [KEY_ONE, KEY_LAST, TEST_PRIV] {
    let key = @secp256k1.PrivateKey::from_bytes(
      @codec.bytes_of_digits(key_digits),
    )
    for digest_digits in digests {
      let digest = @codec.bytes_of_digits(digest_digits)
      let wire = key.sign(digest).to_bytes()
      assert_eq(
        @secp256k1.Signature::from_bytes(wire).recover(digest),
        key.public_key(),
      )
    }
  }
}

///|
/// The offset is the caller's context and nothing in the bytes says which:
/// what `to_bytes` added, `from_bytes` takes back off, and the recovery is the
/// same either way.
test "the 27 offset survives both directions" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let digest = @codec.bytes_of_digits(FOO_DIGEST)
  let signature = key.sign(digest)
  let wire = signature.to_bytes(v_offset=27)
  assert_eq(wire[64], b'\x1c')
  let parsed = @secp256k1.Signature::from_bytes(wire, v_offset=27)
  assert_eq(parsed.recovery_id(), signature.recovery_id())
  assert_eq(parsed.to_bytes(v_offset=27), wire)
  assert_eq(parsed.recover(digest), key.public_key())
}

///|
/// The recovery id is the only thing that picks between the points `r` names,
/// so a wrong one must never land on the signer. Each of the other three
/// either recovers somebody else or has no answer at all.
test "a wrong recovery id never recovers the signer" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let digest = @codec.bytes_of_digits(FOO_DIGEST)
  let signature = key.sign(digest)
  let wire = signature.to_bytes()
  for id in [0, 1, 2, 3] {
    guard id != signature.recovery_id() else { continue }
    let wrong = Bytes::makei(65, i => {
      if i == 64 {
        id.to_byte()
      } else {
        wire[i]
      }
    })
    let parsed = @secp256k1.Signature::from_bytes(wrong)
    // Two of the three name a real point and recover somebody else's key; the
    // high ones name none at all, since this `r` plus N leaves the field.
    assert_not_eq(parsed.recover(digest), key.public_key()) catch {
      @secp256k1.InvalidSignature(_) => ()
      e => raise e
    }
  }
}

///|
/// Assert that `digits` is not a signature, and with which complaint.
fn refuses(
  digits : String,
  expected : @secp256k1.CurveError,
  v_offset? : Int = 0,
) -> Unit raise {
  raises(digits, expected, () => {
    @secp256k1.Signature::from_bytes(@codec.bytes_of_digits(digits), v_offset~)
    |> ignore
  })
}

///|
/// A signature is exactly 65 bytes: two scalars and the id byte. Anything else
/// is a truncation or a concatenation, not a shorter spelling.
test "a signature that is not 65 bytes is refused" {
  let expected = @secp256k1.InvalidLength("signature must be 65 bytes")
  refuses("", expected)
  refuses("01", expected)
  refuses(
    "d155e94305af7e07dd8c32873e5c03cb95c9e05960ef85be9c07f671da58c737" +
    "18c19adc397a211aa9e87e519e2038c5a3b658618db335f74f800b8e0cfeef44",
    expected,
  )
}

///|
/// Both halves live in `[1, N)`, the same range a key does and for the same
/// reason: zero names nothing and anything at or past N is some other scalar
/// spelled long.
test "a half outside the range is refused" {
  let one = "0000000000000000000000000000000000000000000000000000000000000001"
  let zero = "0000000000000000000000000000000000000000000000000000000000000000"
  let n = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
  let n_minus_one = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"
  refuses(zero + one + "00", @secp256k1.InvalidSignature("r is zero"))
  refuses(one + zero + "00", @secp256k1.InvalidSignature("s is zero"))
  refuses(n + one + "00", @secp256k1.InvalidSignature("r >= N"))
  refuses(one + n + "00", @secp256k1.InvalidSignature("s >= N"))
  // EIP-2: the high `s` of the pair verifies just as well, which is why it is
  // not allowed to exist. `N - 1` is the highest there is.
  refuses(
    one + n_minus_one + "00",
    @secp256k1.InvalidSignature("s is not the low half"),
  )
}

///|
/// The id is two bits. Anything else means the offset the caller passed is not
/// the one the bytes were written with — a `27`-flavoured `v` read as a bare
/// one, or the other way round.
test "a recovery id outside 0..=3 is refused" {
  let halves = "0000000000000000000000000000000000000000000000000000000000000001" +
    "0000000000000000000000000000000000000000000000000000000000000001"
  let expected = @secp256k1.InvalidSignature("recovery id out of range")
  refuses(halves + "04", expected)
  refuses(halves + "1b", expected)
  refuses(halves + "ff", expected)
  // The same bytes with the offset the writer used are fine; with one the
  // writer did not use, the id goes negative.
  refuses(halves + "01", expected, v_offset=27)
  @secp256k1.Signature::from_bytes(
    @codec.bytes_of_digits(halves + "1c"),
    v_offset=27,
  )
  |> ignore
}

///|
/// A signature can be well formed and still name no key. Each row is 65 valid
/// wire bytes recovered against the geth digest, and the answer it has none of.
test "a signature that names no point recovers nothing" {
  let one = "0000000000000000000000000000000000000000000000000000000000000001"
  let rows = [
    // Half the field is not a square, so half the possible `r` values are no
    // point's x coordinate at all. `5` is the smallest of them.
    (
      "0000000000000000000000000000000000000000000000000000000000000005" +
      one +
      "00",
      @secp256k1.InvalidSignature("r is no point's x coordinate"),
    ),
    // The high recovery ids claim the x coordinate wrapped past N, so `r + N`
    // is the real one — and for an `r` this large that is past the field
    // order, where no coordinate lives. `p - N` is about `2^129`, so only an
    // `r` under that can carry a high id, which is why no signer has ever
    // emitted one.
    (
      "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140" +
      one +
      "02",
      @secp256k1.InvalidSignature("r + N is past the field order"),
    ),
    (
      "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140" +
      one +
      "03",
      @secp256k1.InvalidSignature("r + N is past the field order"),
    ),
  ]
  for row in rows {
    let (signature_digits, expected) = row
    let signature = @secp256k1.Signature::from_bytes(
      @codec.bytes_of_digits(signature_digits),
    )
    raises(signature_digits, expected, () => {
      signature.recover(@codec.bytes_of_digits(FOO_DIGEST)) |> ignore
    })
  }
}

///|
/// Recovery takes a 32-byte digest for the reason signing does, and says so
/// the same way.
test "recovering against a digest that is not 32 bytes is refused" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let signature = key.sign(@codec.bytes_of_digits(FOO_DIGEST))
  for
    wrong in [
      Bytes::new(0),
      @codec.bytes_of_digits("01"),
      Bytes::make(33, b'\x01'),
    ] {
    raises("\{wrong}", @secp256k1.InvalidLength("digest must be 256 bits"), () => {
      signature.recover(wrong) |> ignore
    })
  }
}
