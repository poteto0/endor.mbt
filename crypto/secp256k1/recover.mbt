///|
/// The public key that signed `digest`: ecrecover. `r` names up to four points
/// and the recovery id says which, so an Ethereum transaction carries no public
/// key at all.
///
/// It answers with uncompressed SEC1 bytes rather than an `Address`, which is
/// `types`' — `Address::recover` is this with the derivation on the end.
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
  // the cheaper ladder: `scalar_base_mult` adds by `madd-2007-bl`, an affine
  // second operand the generic `add` cannot assume.
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
