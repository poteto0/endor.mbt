///|
/// Bytes an HMAC-SHA-256 produces, which is also the width of a scalar — the
/// reason RFC 6979 needs no truncation on this curve.
const HMAC_BYTES = 32

///|
fn hmac_sha256(key : Bytes, message : Bytes) -> Bytes {
  let mac = @crypto.hmac(@crypto.SHA256::new(), key[:], message[:])
  Bytes::makei(HMAC_BYTES, i => mac[i])
}

///|
/// The generator RFC 6979 specifies: HMAC-SHA-256 in counter mode, seeded with
/// the private key and the digest, producing candidate nonces one after
/// another.
///
/// Deterministic on purpose. ECDSA leaks the private key outright if a nonce
/// ever repeats across two different messages, and a generator that cannot
/// repeat unless the message does is a stronger guarantee than any source of
/// randomness can give — which is why every Ethereum signer uses this rather
/// than `@env.rand`.
priv struct Nonces {
  mut key : Bytes
  mut value : Bytes
}

///|
/// Steps a through e of RFC 6979 §3.2: fold the private key and the digest
/// into the generator's state.
fn Nonces::new(scalar : @bigint.BigInt, digest : Bytes) -> Nonces {
  let seed = scalar.to_octets(length=COORD_BYTES) + bits_to_octets(digest)
  let self = {
    key: Bytes::make(HMAC_BYTES, b'\x00'),
    value: Bytes::make(HMAC_BYTES, b'\x01'),
  }
  for separator in [b'\x00', b'\x01'] {
    self.key = hmac_sha256(
      self.key,
      self.value + Bytes::make(1, separator) + seed,
    )
    self.value = hmac_sha256(self.key, self.value)
  }
  self
}

///|
/// The next candidate. Step h: the generator is asked again — after being
/// stirred — for every candidate the caller turns down.
fn Nonces::next(self : Nonces) -> @bigint.BigInt {
  self.value = hmac_sha256(self.key, self.value)
  let candidate = self.value
  self.key = hmac_sha256(self.key, self.value + b"\x00")
  self.value = hmac_sha256(self.key, self.value)
  @bigint.BigInt::from_octets(candidate[:])
}

///|
/// The digest as the scalar RFC 6979 hashes over: one conditional subtraction
/// of the group order, no truncation, since a digest and a scalar are both 256
/// bits on this curve.
fn bits_to_octets(digest : Bytes) -> Bytes {
  let z = match scalar_of_octets(digest) {
    Some(z) => if z >= group_order { z - group_order } else { z }
    // A digest of zero is a scalar of zero. Nothing rules it out, and the
    // generator takes it like any other.
    None => 0N
  }
  z.to_octets(length=COORD_BYTES)
}

///|
/// Sign a 32-byte digest.
///
/// The nonce is derived from the key and the digest by RFC 6979, so signing
/// the same digest with the same key always produces the same signature and
/// nothing here needs a source of randomness.
///
/// This takes a digest and not a message: what gets hashed, and how, is the
/// caller's decision — `keccak256` of an RLP-encoded transaction, of an
/// EIP-191 prefixed message, of an EIP-712 struct. Getting that wrong is how
/// a signature ends up valid for something other than what it was shown for,
/// so this layer does not guess.
///
/// ```
/// let key = @secp256k1.PrivateKey::from_bytes(
///   @codec.bytes_of_digits(
///     "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
///   ),
/// )
/// let signature = key.sign(@keccak.keccak256(b"foo"))
/// assert_eq(signature.recovery_id(), 1)
/// ```
pub fn PrivateKey::sign(
  self : PrivateKey,
  digest : Bytes,
) -> Signature raise CurveError {
  guard digest.length() == COORD_BYTES else {
    raise InvalidLength("digest must be \{COORD_BYTES * 8} bits")
  }
  let z = match scalar_of_octets(bits_to_octets(digest)) {
    Some(z) => z
    None => 0N
  }
  let nonces = Nonces::new(self.scalar, digest)
  // Step h asks again for a candidate that is out of range, and for the two
  // degenerate signatures. None of the three has ever been seen on this curve;
  // the loop is here because leaving it out is how an implementation signs
  // with a nonce it should have rejected.
  for ;; {
    let k = nonces.next()
    guard k >= 1N && k < group_order else { continue }
    let (x, y) = scalar_base_mult(k)
    let r = x % group_order
    guard !r.is_zero() else { continue }
    let s = mul_mod_n(
      invert_mod_n(k),
      (z + mul_mod_n(r, self.scalar)) % group_order,
    )
    guard !s.is_zero() else { continue }
    // Which of the four points `r` could name is this one: the parity of `y`,
    // plus a bit for the x that wrapped past the group order.
    let recovery_id = (y % 2N).to_int() + (if x >= group_order { 2 } else { 0 })
    // Both `s` and `group_order - s` verify, so the canonical signature is the
    // lower one — and taking it reflects the point across the x axis, which
    // flips the parity bit the recovery id just recorded.
    return if s > half_group_order {
      { r, s: group_order - s, recovery_id: recovery_id ^ 1 }
    } else {
      { r, s, recovery_id }
    }
  }
}
