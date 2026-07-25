///|
/// Ethereum's keccak256 — the pre-standardization Keccak, *not* NIST SHA3-256.
/// The two differ only in the domain-separation byte appended during padding
/// (`0x01` here, `0x06` for SHA3), which is enough to make every output differ.
///
/// The state is 1600 bits = 25 lanes of 64 bits, addressed as a 5x5 grid where
/// `A[x][y]` lives at `lanes[x + 5 * y]`.
const LANES = 25

///|
/// Bytes absorbed per permutation: `(1600 - 2 * 256) / 8`. The 512 bits of
/// capacity left over are never touched by input, which is what the security
/// claim rests on.
const RATE = 136

///|
/// `RATE` in whole lanes, i.e. how many lanes a block of input covers.
const RATE_LANES = 17

///|
/// The digest is 32 bytes, which fits in one squeeze because it is below
/// `RATE` — no extra permutation is needed to produce it.
const DIGEST_SIZE = 32

///|
/// The domain-separation byte `pad10*1` appends for Ethereum's keccak256. SHA3
/// uses `0x06` in the same position; nothing else about the two differs.
const KECCAK_PAD : Byte = 0x01

///|
/// Round constants for iota, one per round of `keccak-f[1600]`. They exist only
/// to break the symmetry that the other four steps preserve.
let round_constants : FixedArray[UInt64] = [
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
  0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
  0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
  0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
  0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]

///|
/// Per-lane left-rotation amounts for rho, indexed the same way as the state
/// (`x + 5 * y`).
let rho_offsets : FixedArray[Int] = [
  0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18,
  2, 61, 56, 14,
]

///|
/// Where pi moves each lane: `A'[y][2x + 3y] = A[x][y]`, precomputed so rho and
/// pi can share one pass.
let pi_targets : FixedArray[Int] = FixedArray::makei(LANES, fn(i) {
  let x = i % 5
  let y = i / 5
  y + 5 * ((2 * x + 3 * y) % 5)
})

///|
/// Rotate left within 64 bits. `n` is always in `0..<64`; a shift of exactly 64
/// is not well defined, so a zero rotation returns the input untouched.
fn rotl64(x : UInt64, n : Int) -> UInt64 {
  if n == 0 {
    x
  } else {
    (x << n) | (x >> (64 - n))
  }
}

///|
/// The `keccak-f[1600]` permutation: 24 rounds of theta, rho, pi, chi, iota,
/// applied to `a` in place.
fn permute(a : FixedArray[UInt64]) -> Unit {
  let c = FixedArray::make(5, 0UL)
  let b = FixedArray::make(LANES, 0UL)
  for round in 0..<round_constants.length() {
    // theta — fold each column into a parity lane, then spread it across the
    // two neighbouring columns so a single bit reaches the whole state.
    for x in 0..<5 {
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
    }
    for x in 0..<5 {
      let d = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1)
      for y in 0..<5 {
        a[x + 5 * y] = a[x + 5 * y] ^ d
      }
    }

    // rho (rotate each lane) and pi (move it elsewhere in the grid) — both are
    // pure relocation, so one pass into a scratch grid does the two of them.
    for i in 0..<LANES {
      b[pi_targets[i]] = rotl64(a[i], rho_offsets[i])
    }

    // chi — the only non-linear step, mixing each lane with the next two in
    // its row.
    for y in 0..<5 {
      for x in 0..<5 {
        a[x + 5 * y] = b[x + 5 * y] ^
          (b[(x + 1) % 5 + 5 * y].lnot() & b[(x + 2) % 5 + 5 * y])
      }
    }

    // iota
    a[0] = a[0] ^ round_constants[round]
  }
}

///|
/// XOR one `RATE`-byte block into the state (little-endian lanes) and permute.
fn absorb(a : FixedArray[UInt64], block : FixedArray[Byte], from : Int) -> Unit {
  for lane in 0..<RATE_LANES {
    let base = from + lane * 8
    let mut word = 0UL
    for k = 7; k >= 0; k = k - 1 {
      word = (word << 8) | block[base + k].to_uint().to_uint64()
    }
    a[lane] = a[lane] ^ word
  }
  permute(a)
}

///|
/// Hash `input` with Ethereum's keccak256, returning exactly 32 bytes.
///
/// ```
/// assert_eq(
///   @crypto.keccak256(b"abc"),
///   b"\x4e\x03\x65\x7a\xea\x45\xa9\x4f\xc7\xd4\x7b\xa8\x26\xc8\xd6\x67\xc0\xd1\xe6\xe3\x3a\x64\xa0\x36\xec\x44\xf5\x8f\xa1\x2d\x6c\x45",
/// )
/// ```
pub fn keccak256(input : Bytes) -> Bytes {
  sponge(input, KECCAK_PAD)
}

///|
/// Absorb `input` a block at a time and squeeze a 32-byte digest.
///
/// `pad` is the domain-separation byte, and the only thing that separates the
/// two hashes built on this permutation: `0x01` for Ethereum's keccak256,
/// `0x06` for NIST SHA3-256. Keeping it a parameter lets the tests check the
/// permutation against SHA3-256 vectors, for which an authoritative reference
/// exists in every standard library.
fn sponge(input : Bytes, pad : Byte) -> Bytes {
  let a = FixedArray::make(LANES, 0UL)
  let bytes = input.to_fixedarray()
  let full_blocks = bytes.length() / RATE
  for block in 0..<full_blocks {
    absorb(a, bytes, block * RATE)
  }

  // The tail always needs one more block, even when the input divides evenly
  // into `RATE`: `pad10*1` appends the `0x01` domain byte and the closing high
  // bit unconditionally. When the tail is 135 bytes the two land on the same
  // byte, which is why the second one is OR-ed in.
  let rest = bytes.length() % RATE
  let tail = FixedArray::make(RATE, b'\x00')
  for i in 0..<rest {
    tail[i] = bytes[full_blocks * RATE + i]
  }
  tail[rest] = pad
  tail[RATE - 1] = tail[RATE - 1] | b'\x80'
  absorb(a, tail, 0)

  // Squeeze. The digest is shorter than `RATE`, so it comes straight off the
  // front of the state with no further permutation.
  Bytes::makei(DIGEST_SIZE, i => (a[i / 8] >> (8 * (i % 8))).to_byte())
}

///|
/// Hash the UTF-8 encoding of a string. This is the form Ethereum identifiers
/// take: a function selector is the first four bytes of the hash of a
/// signature, and an event topic is the whole hash of one.
///
/// ```
/// let selector = @crypto.keccak256_string("transfer(address,uint256)")[0:4]
/// assert_eq(selector, b"\xa9\x05\x9c\xbb"[:])
/// ```
pub fn keccak256_string(input : String) -> Bytes {
  keccak256(@utf8.encode(input))
}
