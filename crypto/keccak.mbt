///|
/// The state is 1600 bits = 25 lanes of 64 bits, addressed as a 5x5 grid where
/// `A[x][y]` lives at `lanes[x + 5 * y]`.
const LANES = 25

///|
/// Bytes absorbed per permutation: `(1600 - 2 * 256) / 8`. The 512 bits of
/// capacity left over are never touched by input, which is what the security
/// claim rests on.
const RATE = 136

///|
/// The digest is 32 bytes, which fits in one squeeze because it is below
/// `RATE` — no extra permutation is needed to produce it.
const DIGEST_SIZE = 32

///|
/// The domain-separation byte `pad10*1` appends. See `keccak256`.
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
fn _left_idx(x : Int, n? : Int = 1, len? : Int = 5) -> Int {
  (x + (5 - n)) % len
}

///|
fn _right_idx(x : Int, n? : Int = 1, len? : Int = 5) -> Int {
  (x + n) % len
}

///|
/// theta — fold each column into a parity lane, then spread it across the
/// two neighbouring columns so a single bit reaches the whole state.
fn do_theta_step(a : FixedArray[UInt64]) -> Unit {
  let c = FixedArray::make(5, 0UL)
  // parity bit
  // EX for 4 bit
  // c := [0010 1110 1100 1001 1111]
  for x in 0..<5 {
    c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
  }

  for x in 0..<5 {
    // EX for x = 1
    // 0010 xor 1001 => d := 1011
    let d = c[_left_idx(x)] ^ rotl64(c[_right_idx(x)], 1)
    for y in 0..<5 {
      // embed c back to a
      a[x + 5 * y] = a[x + 5 * y] ^ d
    }
  }
}

///|
/// rho (rotate each lane) and pi (move it elsewhere in the grid) — both are
/// pure relocation, so one pass into a scratch grid does the two of them.
fn do_rho_and_pi_step(a : FixedArray[UInt64]) -> FixedArray[UInt64] {
  let b = FixedArray::make(LANES, 0UL)
  for i in 0..<LANES {
    b[pi_targets[i]] = rotl64(a[i], rho_offsets[i])
  }

  b
}

///|
///  chi — the only non-linear step, mixing each lane with the next two in
/// its row.
/// make it irreversible
/// 
fn do_chi_step(a : FixedArray[UInt64], b : FixedArray[UInt64]) -> Unit {
  for y in 0..<5 {
    let row = 5 * y
    for x in 0..<5 {
      // reverse self lane if next lane = 0 & next-next lane = 1
      a[row + x] = b[row + x] ^
        (b[row + _right_idx(x)].lnot() & b[row + _right_idx(x, n=2)])
    }
  }
}

///|
/// The `keccak-f[1600]` permutation: 24 rounds of theta, rho, pi, chi, iota,
/// applied to `a` in place.
fn permute(a : FixedArray[UInt64]) -> Unit {
  for round in 0..<round_constants.length() {
    do_theta_step(a)
    let b = do_rho_and_pi_step(a)
    do_chi_step(a, b)

    // iota
    a[0] = a[0] ^ round_constants[round]
  }
}

///|
/// XOR one `RATE`-byte block into the state (little-endian lanes) and permute.
///
/// The unchecked read is sound by construction: `from` only ever names the
/// start of a whole block, so every lane lies within `from ..< from + RATE`,
/// and the caller never passes a block that stops short of that.
fn absorb(a : FixedArray[UInt64], block : Bytes, from : Int) -> Unit {
  for lane in 0..<(RATE / 8) {
    a[lane] = a[lane] ^ block.unsafe_read_uint64_le(from + lane * 8)
  }
  permute(a)
}

///|
/// Hash `input` with Ethereum's keccak256, returning exactly 32 bytes.
///
/// This is the pre-standardization Keccak, **not** NIST SHA3-256. The two share
/// a permutation, a rate and a sponge, and differ only in the byte `pad10*1`
/// appends — `0x01` here against SHA3's `0x06`. That single byte makes every
/// output differ, so a SHA3-256 routine can never stand in for this one.
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
/// `pad` is the domain-separation byte described on `keccak256`. It stays a
/// parameter so the tests can drive this against SHA3-256's published vectors,
/// which is the only external authority available — no standard library ships
/// keccak256 itself.
fn sponge(input : Bytes, pad : Byte) -> Bytes {
  let a = FixedArray::make(LANES, 0UL)
  let full_blocks = input.length() / RATE
  for block in 0..<full_blocks {
    absorb(a, input, block * RATE)
  }

  // The tail always needs one more block, even when the input divides evenly
  // into `RATE`: `pad10*1` appends the domain byte and the closing high bit
  // unconditionally. When the tail is 135 bytes the two land on the same byte,
  // which is why the closing bit is OR-ed rather than assigned.
  let rest = input.length() % RATE
  let tail = Bytes::makei(RATE, i => {
    let byte = if i < rest {
      input[full_blocks * RATE + i]
    } else if i == rest {
      pad
    } else {
      b'\x00'
    }
    if i == RATE - 1 {
      byte | b'\x80'
    } else {
      byte
    }
  })
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
