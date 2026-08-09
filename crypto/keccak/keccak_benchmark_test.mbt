///|
test "bench: keccak256" (b : @bench.T) {
  let small = b"abc"
  let big = Bytes::makei(100_000, i => (i % 251).to_byte())
  b.bench(name="small", fn() { ignore(@keccak.keccak256(small)) })
  b.bench(name="big", fn() { ignore(@keccak.keccak256(big)) })
}
