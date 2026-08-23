///|
/// The lowercase spelling a node answers with, and the same address as a human
/// would paste it — the two forms `from_string` tells apart.
const LOWER_ADDRESS : String = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"

///|
const MIXED_ADDRESS : String = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

///|
/// Parsing an address, from either side of the checksum rule.
///
/// Lowercase is what every decode path carries, so it is the row that has to
/// stay free of `keccak256`; mixed case still proves one. The last two price a
/// display — the first one, which hashes, and every one after.
test "bench: address" (b : @bench.T) {
  let parsed = address(LOWER_ADDRESS)
  b.bench(name="from_string, lowercase", fn() {
    b.keep(
      @types.Address::from_string(LOWER_ADDRESS) catch {
        e => abort("from_string: \{e}")
      },
    )
  })
  b.bench(name="from_string, mixed case", fn() {
    b.keep(
      @types.Address::from_string(MIXED_ADDRESS) catch {
        e => abort("from_string: \{e}")
      },
    )
  })
  b.bench(name="to_checksum_string, fresh address", fn() {
    b.keep(address(LOWER_ADDRESS).to_checksum_string())
  })
  b.bench(name="to_checksum_string, memoized", fn() {
    b.keep(parsed.to_checksum_string())
  })
}
