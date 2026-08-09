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
