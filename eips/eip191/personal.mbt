///|
/// [EIP-191](https://eips.ethereum.org/EIPS/eip-191), *signed data*: the shape
/// every signature that is not a transaction is made over.
///
/// ```
/// 0x19 <1 byte version> <version specific data> <data to sign>
/// ```
///
/// The leading `0x19` is the whole point. It is not a valid first byte of an
/// RLP-encoded transaction, so bytes signed this way can never be lifted out
/// and broadcast as one — a dapp cannot show "sign this message" and collect a
/// signature that moves the user's ether. Three versions exist:
///
/// * `0x01` — structured data, which is EIP-712. `@eip712.TypedData::digest`
///   already computes it, so it is not repeated here.
/// * `0x45` (`'E'`) — `personal_sign`, below.
/// * `0x00` — "data with intended validator". Nothing uses it, so nothing here
///   builds it.
///
/// A wallet computes this itself when it signs (`@provider.sign_message`), so
/// signing needs none of it. Verifying does, and that is what this package is
/// for: [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271) asks a contract
/// wallet `isValidSignature(bytes32 hash, bytes signature)`, and somebody has
/// to produce that `hash`. The wallet will not — it hashed the message
/// privately, months ago, and handed back only the signature.
///
/// ```
/// /// Did `signer` — a Safe, or any other contract wallet — sign this text?
/// async fn[P : @provider.Provider] signed_by(
///   p : P,
///   signer : @endor.Address,
///   message : String,
///   signature : @endor.Hex,
/// ) -> Bool raise {
///   // what the signature was made over: the wallet hashed exactly this
///   let hash = @eip191.hash_message(message)
///   // ask the signer itself, because a contract has no key to recover
///   @contract.is_valid_signature(p, signer, hash~, signature~)
/// }
/// ```
///
/// The same call takes an EIP-712 digest — `@eip712.TypedData::digest()` — in
/// place of the first line, because EIP-1271 is told a hash and never asks
/// where it came from. This package is the `personal_sign` half of that
/// choice; `eips/eip712` is the other.

///|
/// The digest behind `personal_sign` — version `0x45`:
///
/// ```text
/// keccak256("\x19Ethereum Signed Message:\n" ‖ len(message) ‖ message)
/// ```
///
/// `len` is the *byte* length written in decimal, and it is what stops one
/// message from being read as another: without it `"abc"` and `"ab" ‖ "c"`
/// would hash the same after concatenation.
///
/// The bytes hashed are the UTF-8 of `message`, matching
/// `@provider.sign_message`, which puts the same bytes on the wire — so a
/// signature obtained there verifies against the digest computed here.
///
/// ```mbt check
/// test "doc: the hash personal_sign signs" {
///   inspect(
///     @eip191.hash_message("Hello, world!"),
///     content="0xb453bd4e271eed985cbab8231da609c4ce0a9cf1f763b6c1594e76315510e0f1",
///   )
/// }
/// ```
pub fn hash_message(message : String) -> @types.Hex {
  hash_bytes(@utf8.encode(message))
}

///|
/// The same digest for a message that is not text.
///
/// `personal_sign` takes bytes — a wallet renders them as text when it can,
/// but a message that is a hash, a nonce or a binary blob is signed just as
/// happily, and its length is counted in bytes either way.
///
/// ```mbt check
/// test "doc: bytes are prefixed by their own length" {
///   inspect(
///     @eip191.hash_bytes(b"Hello, world!"),
///     content="0xb453bd4e271eed985cbab8231da609c4ce0a9cf1f763b6c1594e76315510e0f1",
///   )
/// }
/// ```
pub fn hash_bytes(message : Bytes) -> @types.Hex {
  let prefix = @utf8.encode(
    "\u{19}Ethereum Signed Message:\n\{message.length()}",
  )
  let signed = Bytes::makei(prefix.length() + message.length(), i => {
    if i < prefix.length() {
      prefix[i]
    } else {
      message[i - prefix.length()]
    }
  })
  @types.Hex::from_bytes(@keccak.keccak256(signed))
}
