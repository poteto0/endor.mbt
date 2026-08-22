///|
/// Digits straight into a `@types.Hex`, since every payload below is built out
/// of `word()` rather than parsed from a string a caller wrote.
fn bench_hex(digits : String) -> @types.Hex {
  @types.Hex::from_digits(digits) catch {
    e => abort("bad bench data: \{e}")
  }
}

///|
/// A dynamic array of `count` elements, as it arrives on the wire: the offset
/// to the tail, the length, then the elements.
fn array_data(count : Int) -> @types.Hex {
  let out = StringBuilder::new()
  out.write_string(word("20"))
  out.write_string(word(count.to_string(radix=16)))
  for i in 0..<count {
    out.write_string(word(i.to_string(radix=16)))
  }
  bench_hex(out.to_string())
}

///|
/// One log's non-indexed payload, in the shape a `Transfer`-like event leaves
/// it: three static words, the first of them an address.
fn log_data() -> @types.Hex {
  bench_hex(word(dead().digits()) + word("2a") + word("beef"))
}

///|
/// The same three words with a hash where the address was — the control for
/// the row above, since `Address::from_string` proves an EIP-55 checksum and
/// one `keccak256` per address dwarfs the word reading this file measures.
fn plain_log_data() -> @types.Hex {
  bench_hex(word("beef") + word("2a") + word("beef"))
}

///|
/// Reading back what a node answered.
///
/// Every row is the same word reader seen from a side it is called from — once
/// per element of an array, once per member of a log — so what it measures is
/// what one word costs, multiplied by the only thing a caller can change. The
/// two array rows differ only in whether the element's width has to be proven,
/// which is the one check that goes through `BigInt` rather than digits; the
/// two log rows differ only in the address, which is the one member whose cost
/// is not word reading at all.
test "bench: decode" (b : @bench.T) {
  let wide_types : Array[@abi.AbiType] = [Array(Uint(256))]
  let narrow_types : Array[@abi.AbiType] = [Array(Uint(64))]
  let elements = array_data(1000)
  let log_types : Array[@abi.AbiType] = [Address, Uint(256), FixedBytes(32)]
  let plain_types : Array[@abi.AbiType] = [
    FixedBytes(32),
    Uint(256),
    FixedBytes(32),
  ]
  let log = log_data()
  let plain = plain_log_data()
  b.bench(name="uint256[1000]", fn() {
    b.keep(
      @abi.decode(wide_types, elements) catch {
        e => abort("decode: \{e}")
      },
    )
  })
  b.bench(name="uint64[1000]", fn() {
    b.keep(
      @abi.decode(narrow_types, elements) catch {
        e => abort("decode: \{e}")
      },
    )
  })
  b.bench(name="log x100", fn() {
    for _ in 0..<100 {
      b.keep(@abi.decode(log_types, log) catch { e => abort("decode: \{e}") })
    }
  })
  b.bench(name="log x100, no address", fn() {
    for _ in 0..<100 {
      b.keep(
        @abi.decode(plain_types, plain) catch {
          e => abort("decode: \{e}")
        },
      )
    }
  })
}
