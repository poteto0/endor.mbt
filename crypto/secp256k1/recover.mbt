///|
/// The public key that signed `digest`: ecrecover.
///
/// This is what makes an Ethereum transaction carry no public key. `r` names
/// up to four points, and the recovery id says which; from that point, the
/// digest and `s`, the signer's key falls out as `u1 * G + u2 * R` — no key to
/// be handed, nothing to look up.
///
/// It answers with the uncompressed SEC1 bytes and not an `Address` because
/// this package sits below `types`, which is where `Address` is defined and
/// where the layers only point one way. `Address::recover` is the same
/// recovery with the address derivation on the end, and is what a caller who
/// wants an address should reach for.
///
/// Raises when the signature recovers nothing: an `r` that is no point's x
/// coordinate, a recovery id whose `r + N` is past the field order, or the
/// point at infinity. None of the three can come out of a signer; all three
/// can come off a wire.
///
/// A digest, not a message, for the reason `PrivateKey::sign` takes one — and
/// it must be the *same* digest, since recovery does not verify anything on
/// its own: it answers with whichever key would have signed this digest, so
/// the caller checks that key is the one it expected.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let digest = @keccak.keccak256(b"foo")
/// let recovered = key.sign(digest).recover(digest)
/// assert_eq(recovered, key.public_key())
/// // An address is the layer above: `@types.Address::from_public_key(recovered)`,
/// // or `@types.Address::recover(digest, key.sign(digest))` in one step.
/// ```
pub fn Signature::recover(
  self : Signature,
  digest : Bytes,
) -> Bytes raise CurveError {
  let z = digest_scalar_checked(digest)
  // The two high recovery ids are for the `r` that wrapped: the x coordinate
  // was at or past the group order and `r` is what was left of it. Adding N
  // back can leave the field, and then no point has this x and this id.
  let x = if self.recovery_id >= 2 { self.r + group_order } else { self.r }
  guard x < field_order else {
    raise InvalidSignature("r + N is past the field order")
  }
  let y_squared = add_mod(mul_mod(mul_mod(x, x), x), curve_b)
  guard sqrt_mod_p(y_squared) is Some(root) else {
    raise InvalidSignature("r is no point's x coordinate")
  }
  // Both roots are on the curve; the low bit of the recovery id says which,
  // and `p` being odd means `p - y` has the other parity.
  let y = if (root % 2N).to_int() == (self.recovery_id & 1) {
    root
  } else {
    field_order - root
  }
  let point = Point::{ x, y, z: 1N }
  let r_inv = invert_mod_n(self.r)
  // `-z / r` and `s / r`: the same two coefficients verification would build,
  // read the other way round. `digest_scalar` already reduced `z`, so the
  // negation is one subtraction, with zero its own negative.
  let neg_z = if z.is_zero() { 0N } else { group_order - z }
  let u1 = mul_mod_n(neg_z, r_inv)
  let u2 = mul_mod_n(self.s, r_inv)
  // The two multiplications are spelled differently because the base point has
  // the cheaper ladder: `scalar_base_mult` skips the leading zeros and adds by
  // `madd-2007-bl`, an affine second operand the generic `add` cannot assume.
  // It wants a scalar in `[1, N)`, so the zero `u1` a zero digest gives is the
  // one case handled here rather than there.
  let base_term = if u1.is_zero() {
    Point::infinity()
  } else {
    let (bx, by) = scalar_base_mult(u1)
    Point::{ x: bx, y: by, z: 1N }
  }
  let recovered = base_term.add(scalar_mult(point, u2))
  guard !recovered.is_infinity() else {
    raise InvalidSignature("recovers the point at infinity")
  }
  let (qx, qy) = recovered.to_affine()
  uncompressed(qx, qy)
}
