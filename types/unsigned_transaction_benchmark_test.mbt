///|
/// A word-shaped storage key, distinct per slot so nothing folds them together.
fn storage_key(i : Int) -> @types.Hex {
  @types.Hex::from_bytes(
    @codec.word_left_pad(Bytes::from_array([(i / 256).to_byte(), i.to_byte()])),
  )
}

///|
/// Fifty entries of four slots each — the shape `eth_createAccessList` answers
/// with for a call that walks a few contracts.
fn wide_access_list() -> @types.AccessList raise {
  let entries = []
  for i in 0..<50 {
    let keys = []
    for j in 0..<4 {
      keys.push(storage_key(i * 4 + j))
    }
    entries.push(
      @types.AccessListItem::new(address(RECIPIENT), storage_keys=keys),
    )
  }
  entries
}

///|
/// A fixed signature: what is priced here is the encoding around one, not
/// secp256k1.
const R_WORD : Bytes = b"\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11"

///|
const S_WORD : Bytes = b"\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22\x22"

///|
/// Signing as an account does it: one set of fields, asked for the digest and
/// then for the bytes to broadcast.
fn sign_once(tx : @types.UnsignedTransaction) -> @types.Hex raise {
  let signable = tx.signable()
  signable.signing_digest() |> ignore
  signable.encode_signed(r=R_WORD, s=S_WORD, y_parity=1)
}

///|
/// The same, asked of the transaction itself — which builds the fields once per
/// question. The convenience methods still do this, so it is the row `sign_once`
/// is worth measuring against.
fn sign_per_call(tx : @types.UnsignedTransaction) -> @types.Hex raise {
  tx.signing_digest() |> ignore
  tx.encode_signed(r=R_WORD, s=S_WORD, y_parity=1)
}

///|
/// What one signature costs, over the two transactions where building the
/// fields costs anything: a deploy carrying a hundred kilobytes of bytecode,
/// and a 1559 transaction declaring two hundred storage slots. Both are decoded
/// out of hex on the way into the fields, so one `signable` is exactly what the
/// two signing rows differ by.
///
/// What the rows say is that it is the smaller half: `signing_digest` alone —
/// the RLP and the Keccak over the whole payload, which a signature pays twice
/// whatever it does about the fields — is an order of magnitude more than
/// `signable`.
test "bench: signing a transaction" (b : @bench.T) {
  let deploy = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(3000000),
    data=@types.Hex::from_bytes(Bytes::make(100 * 1024, b'\x60')),
  )
  let wide = @types.UnsignedTransaction::new(
    chain_id=@types.ChainId::mainnet(),
    nonce=@types.Quantity::new(0),
    max_priority_fee_per_gas=@types.Wei::from_gwei("1"),
    max_fee_per_gas=@types.Wei::from_gwei("20"),
    gas=@types.Quantity::new(1000000),
    to=address(RECIPIENT),
    access_list=wide_access_list(),
  )
  let deploy_signable = deploy.signable()
  let wide_signable = wide.signable()
  b.bench(name="deploy 100KB: signable", fn() { b.keep(deploy.signable()) })
  b.bench(name="deploy 100KB: signing_digest", fn() {
    b.keep(deploy_signable.signing_digest())
  })
  b.bench(name="deploy 100KB: sign, one build", fn() {
    b.keep(sign_once(deploy) catch { e => abort("sign: \{e}") })
  })
  b.bench(name="deploy 100KB: sign, build per call", fn() {
    b.keep(sign_per_call(deploy) catch { e => abort("sign: \{e}") })
  })
  b.bench(name="200 slots: signable", fn() { b.keep(wide.signable()) })
  b.bench(name="200 slots: signing_digest", fn() {
    b.keep(wide_signable.signing_digest())
  })
  b.bench(name="200 slots: sign, one build", fn() {
    b.keep(sign_once(wide) catch { e => abort("sign: \{e}") })
  })
  b.bench(name="200 slots: sign, build per call", fn() {
    b.keep(sign_per_call(wide) catch { e => abort("sign: \{e}") })
  })
}
