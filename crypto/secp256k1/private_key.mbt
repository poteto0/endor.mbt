///|
/// A secp256k1 private key, together with the public point it determines.
///
/// The point is derived and encoded once, in the constructor: it takes a
/// scalar multiplication to find, it never changes, and everything a key is
/// for — an address, a signature to recover against — needs it.
///
/// Opaque, because the only way to hold one is through `from_bytes`, which is
/// what makes "a `PrivateKey` is a scalar in `[1, N)`" true of every value of
/// the type.
pub struct PrivateKey {
  priv scalar : @bigint.BigInt
  priv public_key : Bytes
}

///|
/// Read a private key from its big-endian bytes, and derive its public point.
///
/// `strict` is on by default and requires the exact 32 bytes a scalar is
/// written in. Turn it off only to read a key from somewhere that stored it
/// with its leading zeros stripped — a shorter run of bytes names the same
/// scalar, but it is also what a truncated key looks like, so a caller that
/// did not mean to accept one should not.
///
/// Raises unless the scalar is in `[1, N)`. Zero is not a key, and neither is
/// anything at or past the group order: both name the point at infinity or a
/// point some other scalar already names.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// assert_eq(key.public_key().length(), 65)
/// ```
pub fn PrivateKey::from_bytes(
  bytes : Bytes,
  strict? : Bool = true,
) -> PrivateKey raise CurveError {
  guard !strict || bytes.length() == COORD_BYTES else {
    raise InvalidLength("need \{COORD_BYTES * 8} bits")
  }
  guard scalar_of_octets(bytes) is Some(scalar) else {
    raise InvalidKey("zero")
  }
  guard scalar < group_order else { raise InvalidKey(">=N") }
  let (x, y) = scalar_base_mult(scalar)
  // Encode once: the point never changes, and the tagged bytes are the only
  // form anything asks for.
  { scalar, public_key: uncompressed(x, y) }
}

///|
/// The scalar, big-endian in exactly 32 bytes — left-padded with zeros, so the
/// width does not depend on the value.
///
/// ```
/// let digits = "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032"
/// let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(digits))
/// assert_eq(@codec.digits_of_bytes(key.bytes()), digits)
/// ```
pub fn PrivateKey::bytes(self : PrivateKey) -> Bytes {
  self.scalar.to_octets(length=COORD_BYTES)
}

///|
/// The public key in its uncompressed SEC1 form: the tag byte `0x04` followed
/// by the two 32-byte coordinates. This is what an Ethereum address is the
/// Keccak-256 of, minus that tag.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// assert_eq(key.public_key()[0], b'\x04')
/// ```
pub fn PrivateKey::public_key(self : PrivateKey) -> Bytes {
  self.public_key
}
