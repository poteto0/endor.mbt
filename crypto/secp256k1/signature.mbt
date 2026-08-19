///|
/// An ECDSA signature over secp256k1, in the form Ethereum uses.
///
/// `r` and `s` are the signature proper. `recovery_id` is the two bits that
/// say which of the up-to-four points `r` could have come from is the signer's,
/// so a verifier can recover the public key instead of being handed it — which
/// is why an Ethereum transaction carries no public key at all. It is `v` minus
/// whatever offset the context adds (27 for `eth_sign`, none for a typed
/// transaction), so this type holds the raw `0..=3` and leaves the offset to
/// the caller that knows which context it is in.
///
/// `s` is always the lower of the two values that verify. Negating `s` gives
/// another signature that passes verification, which would let anyone flip a
/// transaction's hash without the key; EIP-2 made the high form invalid, so
/// this type only ever holds the low one.
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
/// caller's context rather than the curve's: a typed transaction carries the
/// bare parity bit, because its chain id is already one of the signed fields,
/// while `personal_sign` and `eth_signTypedData_v4` answer with `27` or `28`.
/// The 27 is the older convention, from before EIP-155 made `v` carry a chain
/// id at all.
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
/// Read a signature back off the wire: the exact inverse of `to_bytes`.
///
/// `v_offset` is subtracted from the last byte, and it is the caller's context
/// in the same way it is on the way out — nothing in the 65 bytes says whether
/// they came from a `personal_sign` answer (`27` or `28`) or from a typed
/// transaction (`0` or `1`), so the side that knows says. Pass the same offset
/// both directions and the round trip is the identity.
///
/// Everything the type promises is checked here, because this is the only way
/// bytes become a `Signature`: both halves in `[1, N)`, an `s` in the low half
/// per EIP-2 — the high form verifies just as well, which is why accepting one
/// would let a transaction be re-spelled without the key — and a recovery id in
/// `0..=3`.
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
  // Both halves live in the same range and are read the same way; only the
  // name in the complaint tells them apart.
  fn half(
    digits : BytesView,
    name : String,
  ) -> @bigint.BigInt raise CurveError {
    guard scalar_of_octets(digits.to_owned()) is Some(value) else {
      raise InvalidSignature("\{name} is zero")
    }
    guard value < group_order else { raise InvalidSignature("\{name} >= N") }
    value
  }

  let r = half(bytes[:COORD_BYTES], "r")
  let s = half(bytes[COORD_BYTES:COORD_BYTES * 2], "s")
  guard s <= half_group_order else {
    raise InvalidSignature("s is not the low half")
  }
  let recovery_id = bytes[COORD_BYTES * 2].to_int() - v_offset
  guard recovery_id >= 0 && recovery_id <= 3 else {
    raise InvalidSignature("recovery id out of range")
  }
  { r, s, recovery_id }
}
