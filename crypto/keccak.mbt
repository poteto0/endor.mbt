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
/// A grid of 64-bit lanes, each held as its low and high 32 bits rather than
/// as one `UInt64`.
///
/// The split is what makes this usable on `js`, which is the module's preferred
/// target. `UInt64` compiles to a JavaScript `BigInt` there, and every xor,
/// shift and mask on one allocates an arbitrary-precision heap object — at 24
/// rounds x 25 lanes per permutation that cost is the whole hash. Two `UInt`
/// halves stay in machine words on every backend, so the same code that fixes
/// `js` costs the others only a second 32-bit op where they had one 64-bit one.
priv struct Lanes {
  lo : FixedArray[UInt]
  hi : FixedArray[UInt]
}

///|
fn Lanes::zero(size : Int) -> Lanes {
  { lo: FixedArray::make(size, 0U), hi: FixedArray::make(size, 0U) }
}

///|
/// Round constants for iota, one per round of `keccak-f[1600]`, split into the
/// two halves the state is held in. They exist only to break the symmetry that
/// the other four steps preserve.
let round_constants_lo : FixedArray[UInt] = [
  0x00000001, 0x00008082, 0x0000808a, 0x80008000, 0x0000808b, 0x80000001, 0x80008081,
  0x00008009, 0x0000008a, 0x00000088, 0x80008009, 0x8000000a, 0x8000808b, 0x0000008b,
  0x00008089, 0x00008003, 0x00008002, 0x00000080, 0x0000800a, 0x8000000a, 0x80008081,
  0x00008080, 0x80000001, 0x80008008,
]

///|
let round_constants_hi : FixedArray[UInt] = [
  0x00000000, 0x00000000, 0x80000000, 0x80000000, 0x00000000, 0x00000000, 0x80000000,
  0x80000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x80000000,
  0x80000000, 0x80000000, 0x80000000, 0x80000000, 0x00000000, 0x80000000, 0x80000000,
  0x80000000, 0x00000000, 0x80000000,
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
/// Low half of a 64-bit left-rotation of the lane `(lo, hi)`. `n` is always in
/// `0..<64`; a shift of exactly 0 or 32 would ask for a 32-bit shift by 32,
/// which is not well defined, so both land in their own branch.
fn _rotl64_lo(lo : UInt, hi : UInt, n : Int) -> UInt {
  if n == 0 {
    lo
  } else if n < 32 {
    (lo << n) | (hi >> (32 - n))
  } else if n == 32 {
    hi
  } else {
    let m = n - 32
    (hi << m) | (lo >> (32 - m))
  }
}

///|
/// High half of the same rotation — identical but for the two halves swapping
/// roles, since rotating past 32 bits is what exchanges them.
fn _rotl64_hi(lo : UInt, hi : UInt, n : Int) -> UInt {
  if n == 0 {
    hi
  } else if n < 32 {
    (hi << n) | (lo >> (32 - n))
  } else if n == 32 {
    lo
  } else {
    let m = n - 32
    (lo << m) | (hi >> (32 - m))
  }
}

///|
fn _left_idx(x : Int, n? : Int = 1) -> Int {
  (x + (5 - n)) % 5
}

///|
fn _right_idx(x : Int, n? : Int = 1) -> Int {
  (x + n) % 5
}

///|
/// theta — fold each column into a parity lane, then spread it across the
/// two neighbouring columns so a single bit reaches the whole state.
fn _do_theta_step(a : Lanes, c : Lanes) -> Unit {
  // parity bit
  // EX for 4 bit
  // c := [0010 1110 1100 1001 1111]
  for x in 0..<5 {
    c.lo[x] = a.lo[x] ^ a.lo[x + 5] ^ a.lo[x + 10] ^ a.lo[x + 15] ^ a.lo[x + 20]
    c.hi[x] = a.hi[x] ^ a.hi[x + 5] ^ a.hi[x + 10] ^ a.hi[x + 15] ^ a.hi[x + 20]
  }
  for x in 0..<5 {
    let l = _left_idx(x)
    let r = _right_idx(x)
    // EX for x = 1
    // 0010 xor 1001(rotated) => d := 1011
    //
    // The rotation is by one, so rather than go through `_rotl64_*` each half
    // simply takes the other's top bit.
    let d_lo = c.lo[l] ^ ((c.lo[r] << 1) | (c.hi[r] >> 31))
    let d_hi = c.hi[l] ^ ((c.hi[r] << 1) | (c.lo[r] >> 31))
    for y in 0..<5 {
      // embed c back to a
      let i = x + 5 * y
      a.lo[i] = a.lo[i] ^ d_lo
      a.hi[i] = a.hi[i] ^ d_hi
    }
  }
}

///|
/// rho (rotate each lane) and pi (move it elsewhere in the grid) — both are
/// pure relocation, so one pass into a scratch grid does the two of them.
fn _do_rho_and_pi_step(a : Lanes, b : Lanes) -> Unit {
  for i in 0..<LANES {
    let target = pi_targets[i]
    let n = rho_offsets[i]
    let lo = a.lo[i]
    let hi = a.hi[i]
    b.lo[target] = _rotl64_lo(lo, hi, n)
    b.hi[target] = _rotl64_hi(lo, hi, n)
  }
}

///|
///  chi — the only non-linear step, mixing each lane with the next two in
/// its row.
///
fn _do_chi_step(a : Lanes, b : Lanes) -> Unit {
  for y in 0..<5 {
    let row = 5 * y
    for x in 0..<5 {
      // flip self lane if next lane = 0 & next-next lane = 1
      let self_ = row + x
      let next = row + _right_idx(x)
      let after = row + _right_idx(x, n=2)
      a.lo[self_] = b.lo[self_] ^ (b.lo[next].lnot() & b.lo[after])
      a.hi[self_] = b.hi[self_] ^ (b.hi[next].lnot() & b.hi[after])
    }
  }
}

///|
/// The sponge's working memory: the state plus the two scratch grids the steps
/// need. They live together so a multi-block input allocates them once instead
/// of once per permutation.
priv struct Keccak {
  a : Lanes
  b : Lanes
  c : Lanes
}

///|
fn Keccak::new() -> Keccak {
  { a: Lanes::zero(LANES), b: Lanes::zero(LANES), c: Lanes::zero(5) }
}

///|
/// The `keccak-f[1600]` permutation: 24 rounds of theta, rho, pi, chi, iota,
/// applied to the state in place.
fn Keccak::permute(self : Keccak) -> Unit {
  for round in 0..<round_constants_lo.length() {
    _do_theta_step(self.a, self.c)
    _do_rho_and_pi_step(self.a, self.b)
    _do_chi_step(self.a, self.b)

    // iota
    self.a.lo[0] = self.a.lo[0] ^ round_constants_lo[round]
    self.a.hi[0] = self.a.hi[0] ^ round_constants_hi[round]
  }
}

///|
/// XOR one `RATE`-byte block into the state (little-endian lanes) and permute.
///
/// The unchecked reads are sound by construction: `from` only ever names the
/// start of a whole block, so every lane lies within `from ..< from + RATE`,
/// and the caller never passes a block that stops short of that.
fn Keccak::absorb(self : Keccak, block : Bytes, from : Int) -> Unit {
  for lane in 0..<(RATE / 8) {
    let at = from + lane * 8
    // Little-endian, so the low half is the earlier four bytes.
    self.a.lo[lane] = self.a.lo[lane] ^ block.unsafe_read_uint32_le(at)
    self.a.hi[lane] = self.a.hi[lane] ^ block.unsafe_read_uint32_le(at + 4)
  }
  self.permute()
}

///|
/// Hash `input` with Ethereum's keccak256, returning exactly 32 bytes.
///
/// This is the pre-standardization Keccak, **not** NIST SHA3-256. The two share
/// a permutation, a rate and a sponge, and differ only in the byte `pad10*1`
/// appends — `0x01` here against SHA3's `0x06`. That single byte makes every
/// output differ, so a SHA3-256 routine can never stand in for this one.
///
/// ```mbt check
/// test "doc: test keccak256" {
///   assert_eq(
///     @crypto.keccak256(b"abc"),
///     b"\x4e\x03\x65\x7a\xea\x45\xa9\x4f\xc7\xd4\x7b\xa8\x26\xc8\xd6\x67\xc0\xd1\xe6\xe3\x3a\x64\xa0\x36\xec\x44\xf5\x8f\xa1\x2d\x6c\x45",
///   )
/// }
/// ```
pub fn keccak256(input : Bytes) -> Bytes {
  _sponge(input, KECCAK_PAD)
}

///|
/// Absorb `input` a block at a time and squeeze a 32-byte digest.
///
/// `pad` is the domain-separation byte described on `keccak256`. It stays a
/// parameter so the tests can drive this against SHA3-256's published vectors,
/// which is the only external authority available — no standard library ships
/// keccak256 itself.
fn _sponge(input : Bytes, pad : Byte) -> Bytes {
  let k = Keccak::new()
  let full_blocks = input.length() / RATE
  for block in 0..<full_blocks {
    k.absorb(input, block * RATE)
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
  k.absorb(tail, 0)

  // Squeeze. The digest is shorter than `RATE`, so it comes straight off the
  // front of the state with no further permutation.
  Bytes::makei(DIGEST_SIZE, i => {
    let byte = i % 8
    let half = if byte < 4 { k.a.lo[i / 8] } else { k.a.hi[i / 8] }
    (half >> (8 * (byte % 4))).to_byte()
  })
}

///|
/// Hash the UTF-8 encoding of a string. This is the form Ethereum identifiers
/// take: a function selector is the first four bytes of the hash of a
/// signature, and an event topic is the whole hash of one.
///
/// ```mbt check
/// test "doc: keccack string" {
///   let selector = @crypto.keccak256_string("transfer(address,uint256)")[0:4]
///   assert_eq(selector, b"\xa9\x05\x9c\xbb"[:])
/// }
/// ```
pub fn keccak256_string(input : String) -> Bytes {
  keccak256(@utf8.encode(input))
}
