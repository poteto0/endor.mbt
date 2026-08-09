///|
/// go-ethereum's `crypto_test.go` test key, and the address it derives.
const TEST_PRIV = "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032"

///|
const TEST_ADDR = "970e8128ab834e8eac17ab8e3812f010678cf791"

///|
/// The two ends of the range a key can be in.
const KEY_ONE = "0000000000000000000000000000000000000000000000000000000000000001"

///|
const KEY_LAST = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"

///|
/// The address a public key derives: the last 20 bytes of the Keccak-256 of the
/// coordinates, with the SEC1 tag byte left off. It is `types` that owns
/// `Address`, and `types` is built on this package, so the derivation is spelled
/// out here rather than reached for.
fn address_of(key : @secp256k1.PrivateKey) -> String {
  let public_key = key.public_key()
  let hash = @crypto.keccak256(public_key[1:].to_owned())
  @codec.digits_of_bytes(hash[12:].to_owned())
}

///|
/// Assert that `bytes` is turned away, and with which complaint.
fn rejects(
  bytes : Bytes,
  expected : @secp256k1.CurveError,
  strict? : Bool = true,
) -> Unit raise {
  try @secp256k1.PrivateKey::from_bytes(bytes, strict~) |> ignore catch {
    e => assert_eq(e, expected)
  } noraise {
    _ => fail("expected \{expected} for \{bytes}")
  }
}

///|
test "public key derives the known address" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  assert_eq(address_of(key), TEST_ADDR)
}

///|
test "the scalar survives the round trip" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  assert_eq(@codec.digits_of_bytes(key.bytes()), TEST_PRIV)
}

///|
/// `1 * G` is G, so the smallest key there is pins the base point and the
/// uncompressed encoding at once.
test "the key 1 is the base point" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(KEY_ONE))
  assert_eq(
    @codec.digits_of_bytes(key.public_key()),
    "04" +
    "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" +
    "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8",
  )
}

///|
/// `(N - 1) * G` is `-G`: the same x, and the y reflected across the field.
/// Nothing but a correct addition chain over the whole 256 bits lands there.
test "the largest key is the base point negated" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(KEY_LAST))
  assert_eq(
    @codec.digits_of_bytes(key.public_key()),
    "04" +
    "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" +
    "b7c52588d95c3b9aa25b0403f1eef75702e84bb7597aabe663b82f6f04ef2777",
  )
}

///|
/// go-ethereum's `TestToECDSAErrors`: zero and all-ones are the two ends of
/// what a 32-byte scalar can be and neither is a key.
test "zero is not a key" {
  rejects(Bytes::make(32, b'\x00'), @secp256k1.InvalidKey("zero"))
}

///|
test "a scalar at or past the group order is not a key" {
  rejects(Bytes::make(32, b'\xff'), @secp256k1.InvalidKey(">=N"))
  // N itself, the first scalar that is out of range.
  rejects(
    @codec.bytes_of_digits(
      "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
    ),
    @secp256k1.InvalidKey(">=N"),
  )
}

///|
test "a strict read wants the exact width" {
  let expected = @secp256k1.InvalidLength("need 256 bits")
  rejects(@codec.bytes_of_digits("01"), expected)
  rejects(Bytes::new(0), expected)
}

///|
/// Leading zeros stripped is the same scalar, which is what a lenient read is
/// for. It is still no way around the range check.
test "a lenient read takes a short scalar" {
  let short = @secp256k1.PrivateKey::from_bytes(
    @codec.bytes_of_digits("01"),
    strict=false,
  )
  let padded = @secp256k1.PrivateKey::from_bytes(
    @codec.bytes_of_digits(KEY_ONE),
  )
  assert_eq(short.public_key(), padded.public_key())
  rejects(Bytes::new(0), @secp256k1.InvalidKey("zero"), strict=false)
}

///|
test "the error reads without naming the curve" {
  assert_eq(
    @secp256k1.InvalidKey("zero").message(),
    "That is not a valid private key.",
  )
  assert_eq(
    @secp256k1.InvalidLength("need 256 bits").message(),
    "That private key is the wrong length.",
  )
  assert_false(@secp256k1.InvalidKey("zero").is_retryable())
  inspect(@secp256k1.InvalidKey("zero"), content="InvalidKey(\"zero\")")
}
