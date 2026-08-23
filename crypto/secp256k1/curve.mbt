///|
/// The prime the coordinate field is taken modulo: `2^256 - 2^32 - 977`.
let field_order : @bigint.BigInt = @bigint.BigInt::from_string(
  "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",
  radix=16,
)

///|
/// The order of the base point: how many distinct keys the curve has. A private
/// key is a scalar in `[1, N)`.
let group_order : @bigint.BigInt = @bigint.BigInt::from_string(
  "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
  radix=16,
)

///|
/// Half the group order, rounded down: the line an `s` has to be under for a
/// signature to be the canonical one of its pair. See `Signature`.
let half_group_order : @bigint.BigInt = (group_order - 1N) / 2N

///|
/// `a * b` in the scalar field — modulo the group order, not the field order.
/// Signatures live here; coordinates live in the other one.
fn mul_mod_n(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  a * b % group_order
}

///|
/// `a^-1` in the scalar field, by Fermat, as in `Point::to_affine`.
fn invert_mod_n(a : @bigint.BigInt) -> @bigint.BigInt {
  a.pow(group_order - 2N, modulus=group_order)
}

///|
/// The x coordinate of the base point G.
let base_x : @bigint.BigInt = @bigint.BigInt::from_string(
  "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
  radix=16,
)

///|
/// The y coordinate of the base point G.
let base_y : @bigint.BigInt = @bigint.BigInt::from_string(
  "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8",
  radix=16,
)

///|
/// `7`, the `b` of `y^2 = x^3 + 7` — secp256k1's curve equation, whose `a` is
/// zero, which is why the formulas below have no `a` term.
let curve_b : @bigint.BigInt = 7N

///|
/// Bytes in a coordinate, and in a scalar.
const COORD_BYTES = 32

///|
/// A point in its uncompressed SEC1 form: the tag byte `0x04` and then the two
/// coordinates, each big-endian in exactly 32 bytes. The one place the wire
/// form is spelled — a key derives it once, recovery builds it again.
fn uncompressed(x : @bigint.BigInt, y : @bigint.BigInt) -> Bytes {
  b"\x04" + x.to_octets(length=COORD_BYTES) + y.to_octets(length=COORD_BYTES)
}

///|
/// The scalar a big-endian run of bytes spells, or `None` when that scalar is
/// zero.
///
/// The zero is read off the bytes because `@bigint.BigInt::from_octets` cannot
/// answer for it: it aborts on empty input, and on `native` returns an all-zero
/// value `is_zero` misses. Every scalar read here goes through this.
fn scalar_of_octets(bytes : Bytes) -> @bigint.BigInt? {
  if bytes.iter().any(byte => byte != b'\x00') {
    Some(@bigint.BigInt::from_octets(bytes[:]))
  } else {
    None
  }
}

///|
/// A point in Jacobian coordinates, standing for the affine point
/// `(x / z^2, y / z^3)`. Inversion is the one expensive operation on this
/// curve, and Jacobian coordinates buy a whole scalar multiplication for a
/// single one at the end.
///
/// `z = 0` is the point at infinity.
priv struct Point {
  x : @bigint.BigInt
  y : @bigint.BigInt
  z : @bigint.BigInt
}

///|
/// Operands are always already reduced, so the sum needs at most one
/// subtraction to come back into range.
fn add_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let sum = a + b
  if sum >= field_order {
    sum - field_order
  } else {
    sum
  }
}

///|
/// Borrow rather than let the difference go negative: `%` would keep the sign.
fn sub_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  if a >= b {
    a - b
  } else {
    a + field_order - b
  }
}

///|
fn mul_mod(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  a * b % field_order
}

///|
/// `a * n` for the small `n` the curve formulas multiply by, as a chain of
/// additions.
///
/// Not `a * n % field_order`: the product is under `8p`, and `%` is a full long
/// division whose quotient is thrown away. This runs about 1800 times per
/// scalar multiplication.
fn scale_mod(a : @bigint.BigInt, n : Int) -> @bigint.BigInt {
  let mut total = 0N
  let mut addend = a
  let mut left = n
  while left > 0 {
    if (left & 1) == 1 {
      total = add_mod(total, addend)
    }
    addend = add_mod(addend, addend)
    left = left >> 1
  }
  total
}

///|
/// `dbl-2009-l`, the formula for `a = 0` curves.
fn Point::double(self : Point) -> Point {
  let a = mul_mod(self.x, self.x)
  let b = mul_mod(self.y, self.y)
  let c = mul_mod(b, b)
  let xb = add_mod(self.x, b)
  let d = scale_mod(sub_mod(sub_mod(mul_mod(xb, xb), a), c), 2)
  let e = scale_mod(a, 3)
  let f = mul_mod(e, e)
  let x = sub_mod(f, scale_mod(d, 2))
  {
    x,
    y: sub_mod(mul_mod(e, sub_mod(d, x)), scale_mod(c, 8)),
    z: scale_mod(mul_mod(self.y, self.z), 2),
  }
}

///|
/// `self + G`, by `madd-2007-bl` — the addition formula for a second operand
/// that is affine, which the base point always is.
///
/// `self` must be neither infinity nor `±G`, which the ladder below guarantees
/// by always doubling first. That is why there is no case for a zero `h`.
fn Point::add_base(self : Point) -> Point {
  let zz = mul_mod(self.z, self.z)
  let u2 = mul_mod(base_x, zz)
  let s2 = mul_mod(mul_mod(base_y, self.z), zz)
  let h = sub_mod(u2, self.x)
  let hh = mul_mod(h, h)
  let i = scale_mod(hh, 4)
  let j = mul_mod(h, i)
  let r = scale_mod(sub_mod(s2, self.y), 2)
  let v = mul_mod(self.x, i)
  let x = sub_mod(sub_mod(mul_mod(r, r), j), scale_mod(v, 2))
  let zh = add_mod(self.z, h)
  {
    x,
    y: sub_mod(mul_mod(r, sub_mod(v, x)), scale_mod(mul_mod(self.y, j), 2)),
    z: sub_mod(sub_mod(mul_mod(zh, zh), zz), hh),
  }
}

///|
/// The exponent that inverts a field element, since `z^(p - 2)` is `z^-1` for a
/// prime field. Held here because it is a constant of the curve, not something
/// to rebuild per key.
let inverse_exponent : @bigint.BigInt = field_order - 2N

///|
/// The affine `(x, y)`. Infinity has none and cannot reach here — see the
/// ladder.
fn Point::to_affine(self : Point) -> (@bigint.BigInt, @bigint.BigInt) {
  // One inversion for the whole scalar multiplication, which is what Jacobian
  // coordinates are for.
  let z_inv = self.z.pow(inverse_exponent, modulus=field_order)
  let zz_inv = mul_mod(z_inv, z_inv)
  (mul_mod(self.x, zz_inv), mul_mod(self.y, mul_mod(zz_inv, z_inv)))
}

///|
/// `k * G` in affine coordinates, by double-and-add over the bits of `k`, most
/// significant first.
///
/// `k` must be in `[1, N)`, so it has a highest set bit and the ladder starts at
/// G there. Every value it holds is some `m * G` with `0 < m < N`, so none is
/// infinity, and `m` is always even where it adds.
fn scalar_base_mult(k : @bigint.BigInt) -> (@bigint.BigInt, @bigint.BigInt) {
  let mut acc = Point::base()
  let mut started = false
  for byte in k.to_octets(length=COORD_BYTES) {
    for bit = 7; bit >= 0; bit = bit - 1 {
      let is_set = ((byte.to_int() >> bit) & 1) == 1
      if started {
        acc = acc.double()
        if is_set {
          acc = acc.add_base()
        }
      } else {
        // The first set bit is G itself, which `acc` already holds.
        started = is_set
      }
    }
  }
  acc.to_affine()
}

///|
/// The point at infinity, the identity of the group. Any `z = 0` is it; this
/// is the representative everything here builds.
fn Point::infinity() -> Point {
  { x: 1N, y: 1N, z: 0N }
}

///|
/// The base point G, as a Jacobian point. Affine coordinates are the `z = 1`
/// case, so this is `(base_x, base_y)` with nothing to divide by.
fn Point::base() -> Point {
  { x: base_x, y: base_y, z: 1N }
}

///|
/// Whether this is the identity. Jacobian coordinates say so with a zero `z`,
/// there being no affine `(x / 0, y / 0)`.
fn Point::is_infinity(self : Point) -> Bool {
  self.z.is_zero()
}

///|
/// `self + other`, by `add-2007-bl` — the general addition, for two operands
/// that are both projective and may be anything.
///
/// `Point::add_base` stays where it is: the signing path runs it about 256 times
/// per signature and must not pay for the cases here. Those cases are infinity
/// on either side, and `h == 0`, where the chord does not exist.
fn Point::add(self : Point, other : Point) -> Point {
  if self.is_infinity() {
    return other
  }
  if other.is_infinity() {
    return self
  }
  let z1z1 = mul_mod(self.z, self.z)
  let z2z2 = mul_mod(other.z, other.z)
  let u1 = mul_mod(self.x, z2z2)
  let u2 = mul_mod(other.x, z1z1)
  let s1 = mul_mod(mul_mod(self.y, other.z), z2z2)
  let s2 = mul_mod(mul_mod(other.y, self.z), z1z1)
  let h = sub_mod(u2, u1)
  let r = scale_mod(sub_mod(s2, s1), 2)
  if h.is_zero() {
    return if r.is_zero() { self.double() } else { Point::infinity() }
  }
  let hh = mul_mod(h, h)
  let i = scale_mod(hh, 4)
  let j = mul_mod(h, i)
  let v = mul_mod(u1, i)
  let x = sub_mod(sub_mod(mul_mod(r, r), j), scale_mod(v, 2))
  let z_sum = add_mod(self.z, other.z)
  {
    x,
    y: sub_mod(mul_mod(r, sub_mod(v, x)), scale_mod(mul_mod(s1, j), 2)),
    z: mul_mod(sub_mod(sub_mod(mul_mod(z_sum, z_sum), z1z1), z2z2), h),
  }
}

///|
/// `k * point`, by double-and-add over the bits of `k`, most significant first.
///
/// Unlike `scalar_base_mult` this takes any `k`, including zero, and any point,
/// so the accumulator starts at infinity. That costs next to nothing — the cost
/// of this ladder is its 256 general additions, not its start.
fn scalar_mult(point : Point, k : @bigint.BigInt) -> Point {
  let mut acc = Point::infinity()
  for byte in k.to_octets(length=COORD_BYTES) {
    for bit = 7; bit >= 0; bit = bit - 1 {
      acc = acc.double()
      if ((byte.to_int() >> bit) & 1) == 1 {
        acc = acc.add(point)
      }
    }
  }
  acc
}

///|
/// The exponent that takes a square root in the coordinate field: `(p + 1) / 4`.
///
/// It works because `p ≡ 3 (mod 4)` on this curve, which makes `a^((p+1)/4)` a
/// square root of `a` whenever `a` has one at all. It does not say whether `a`
/// has one, so the caller squares the answer back.
let sqrt_exponent : @bigint.BigInt = (field_order + 1N) / 4N

///|
/// A square root of `a` in the coordinate field, or `None` when `a` is not a
/// square there — half the field is not, and an `r` that is no point's x
/// coordinate is exactly that case.
///
/// Which of the two roots comes back is not specified; `-root` is the other,
/// and the caller picks by parity.
fn sqrt_mod_p(a : @bigint.BigInt) -> @bigint.BigInt? {
  let root = a.pow(sqrt_exponent, modulus=field_order)
  // The exponent answers for every input; only squaring back says whether the
  // answer is a root or a leftover.
  if mul_mod(root, root) == a {
    Some(root)
  } else {
    None
  }
}
