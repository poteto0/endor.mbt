///|
/// Draw a nonce: 32 bytes off the platform's own CSPRNG.
///
/// The nonce is what the token marks as used, so it has to be *drawn* and not
/// counted: one a third party can predict is an authorization that party can
/// burn before the intended submitter gets to it.
///
/// EIP-3009's nonce alone. EIP-2612's is the other kind — `nonces(owner)` read
/// off the token, a counter and a `BigInt` — so nothing drawn here goes into a
/// `@eip2612.Permit`.
///
/// ```mbt check
/// test "doc: draw a nonce" {
///   inspect(draw_nonce().byte_length(), content="32")
/// }
/// ```
pub fn draw_nonce() -> @types.Hex raise @types.CodecError {
  guard @env.rand(32) is Some(entropy) else {
    raise @types.InvalidValue("this target has no entropy source")
  }
  @types.Hex::from_bytes(entropy)
}
