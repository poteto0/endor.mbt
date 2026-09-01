///|
/// A secp256k1 private key, together with the public point it determines.
///
/// The point is derived once, in the constructor: it takes a scalar
/// multiplication to find and never changes. Opaque, because `from_bytes` is
/// the only way to hold one — which is what makes "a `PrivateKey` is a scalar
/// in `[1, N)`" true of every value of the type.
///
/// Not constant time. The ladder walks a fixed 256 bits, so the doubling count
/// no longer follows the scalar's length, but additions still track its bits
/// and the `BigInt` under them is value-dependent throughout. Anyone who can
/// time this process learns something about the scalars it multiplies.
pub struct PrivateKey {
  priv scalar : @bigint.BigInt
  priv public_key : Bytes
}

///|
/// Read a private key from its big-endian bytes, and derive its public point.
///
/// `strict` is on by default and requires the exact 32 bytes. Turn it off only
/// to read a key stored with its leading zeros stripped — which is also what a
/// truncated key looks like. Raises unless the scalar is in `[1, N)`.
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
