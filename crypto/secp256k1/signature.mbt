///|
/// An ECDSA signature over secp256k1, in the form Ethereum uses.
///
/// `recovery_id` is the two bits saying which of the points `r` could name is
/// the signer's. It is `v` minus whatever offset the context adds, so this type
/// holds the raw `0..=3`. `s` is always the lower of the two values that verify:
/// EIP-2 made the high form invalid, since it re-spells a transaction's hash.
pub struct Signature {
  priv r : @bigint.BigInt
  priv s : @bigint.BigInt
  priv recovery_id : Int
}

///|
/// The 65 bytes a signature goes on the wire as: `r`, then `s`, then the
/// recovery id as a single byte.
///
/// `v_offset` is added to that last byte, and which offset to use is the
/// caller's context: a typed transaction carries the bare parity bit, while
/// `personal_sign` and `eth_signTypedData_v4` answer with `27` or `28`.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let signature = key.sign(@keccak.keccak256(b"foo"))
/// assert_eq(signature.to_bytes().length(), 65)
/// assert_eq(signature.to_bytes(v_offset=27)[64], b'\x1c')
/// ```
pub fn Signature::to_bytes(self : Signature, v_offset? : Int = 0) -> Bytes {
  self.r() + self.s() + Bytes::make(1, (self.recovery_id + v_offset).to_byte())
}

///|
/// The `r` half, big-endian in 32 bytes.
pub fn Signature::r(self : Signature) -> Bytes {
  self.r.to_octets(length=COORD_BYTES)
}

///|
/// The `s` half, big-endian in 32 bytes. Always the low one of the pair.
pub fn Signature::s(self : Signature) -> Bytes {
  self.s.to_octets(length=COORD_BYTES)
}

///|
/// Which of the candidate points `r` names is the signer's: `0..=3`. Add the
/// offset the context wants to get a `v`.
pub fn Signature::recovery_id(self : Signature) -> Int {
  self.recovery_id
}

///|
/// Bytes a signature goes on the wire as: two 32-byte halves and the `v` byte.
const SIGNATURE_BYTES : Int = COORD_BYTES * 2 + 1

///|
/// Read a signature back off the wire: the exact inverse of `to_bytes`. Pass the
/// same `v_offset` both directions and the round trip is the identity.
///
/// Length aside, the checks are `from_halves`', which this splits the bytes
/// for.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let wire = key.sign(@keccak.keccak256(b"foo")).to_bytes(v_offset=27)
/// let signature = @secp256k1.Signature::from_bytes(wire, v_offset=27)
/// assert_eq(signature.recovery_id(), 1)
/// ```
pub fn Signature::from_bytes(
  bytes : Bytes,
  v_offset? : Int = 0,
) -> Signature raise CurveError {
  guard bytes.length() == SIGNATURE_BYTES else {
    raise InvalidLength("signature must be \{SIGNATURE_BYTES} bytes")
  }
  Signature::from_halves(
    r=bytes[:COORD_BYTES].to_owned(),
    s=bytes[COORD_BYTES:COORD_BYTES * 2].to_owned(),
    recovery_id=bytes[COORD_BYTES * 2].to_int() - v_offset,
  )
}

///|
/// A signature from its three parts, for a caller that already has them apart:
/// a transaction and an authorization carry `r`, `s` and the recovery id as
/// three fields rather than as the 65 bytes.
///
/// Everything the type promises is checked here, because every `Signature`
/// comes through here: both halves in `[1, N)`, an `s` in the low half per
/// EIP-2, and a recovery id in `0..=3`.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let signed = key.sign(@keccak.keccak256(b"foo"))
/// let signature = @secp256k1.Signature::from_halves(
///   r=signed.r(),
///   s=signed.s(),
///   recovery_id=signed.recovery_id(),
/// )
/// assert_eq(signature.to_bytes(), signed.to_bytes())
/// ```
pub fn Signature::from_halves(
  r~ : Bytes,
  s~ : Bytes,
  recovery_id~ : Int,
) -> Signature raise CurveError {
  // Both halves live in the same range and are read the same way; only the
  // name in the complaint tells them apart.
  fn half(bytes : Bytes, name : String) -> @bigint.BigInt raise CurveError {
    guard bytes.length() == COORD_BYTES else {
      raise InvalidLength("\{name} must be \{COORD_BYTES} bytes")
    }
    guard scalar_of_octets(bytes) is Some(value) else {
      raise InvalidSignature("\{name} is zero")
    }
    guard value < group_order else { raise InvalidSignature("\{name} >= N") }
    value
  }

  let r = half(r, "r")
  let s = half(s, "s")
  guard s <= half_group_order else {
    raise InvalidSignature("s is not the low half")
  }
  guard recovery_id >= 0 && recovery_id <= 3 else {
    raise InvalidSignature("recovery id out of range")
  }
  { r, s, recovery_id }
}
