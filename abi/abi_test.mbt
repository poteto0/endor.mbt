///|
/// Encoding and decoding both raise, and almost every test in this package is
/// about what comes out rather than about the raising: these helpers turn "it
/// worked" into a string to `inspect`, and make an unexpected failure the
/// test's own problem rather than an expectation to update.
fn encoded(
  types : Array[@abi.AbiType],
  values : Array[@abi.AbiValue],
) -> String {
  let data = @abi.encode(types, values) catch {
    e => abort("unexpected error: \{e}")
  }
  data.to_string()
}

///|
fn decoded(types : Array[@abi.AbiType], data : String) -> String {
  let hex = @types.Hex::from_string(data) catch {
    e => abort("bad test data: \{e}")
  }
  let values = @abi.decode(types, hex) catch {
    e => abort("unexpected error: \{e}")
  }
  @debug.to_string(values)
}

///|
/// The error a call raised, as text. Not raising is itself the answer, so it
/// shows up in the diff instead of aborting the run.
fn refused(f : () -> Unit raise @abi.AbiError) -> String {
  try {
    f()
    "no error"
  } catch {
    e => "\{e}"
  }
}

///|
/// A word of padding then the digits — how every static value reads.
fn word(digits : String) -> String {
  let out = StringBuilder::new()
  for _ in 0..<(64 - digits.length()) {
    out.write_char('0')
  }
  out.write_string(digits)
  out.to_string()
}

///|
/// An address that is memorable in a hex dump.
fn dead() -> @types.Address {
  @types.Address::from_string("0x000000000000000000000000000000000000dead") catch {
    e => abort("bad test address: \{e}")
  }
}
