///|
/// [EIP-191](https://eips.ethereum.org/EIPS/eip-191), *signed data*: the shape
/// every non-transaction signature is made over.
///
/// ```
/// 0x19 <1 byte version> <version specific data> <data to sign>
/// ```
///
/// The leading `0x19` is the whole point: it is not a valid first byte of an
/// RLP-encoded transaction, so bytes signed this way can never be broadcast as
/// one. Version `0x45` (`'E'`) is `personal_sign`, below.
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

///|
/// The digest behind `personal_sign` — version `0x45`:
///
/// ```text
/// keccak256("\x19Ethereum Signed Message:\n" ‖ len(message) ‖ message)
/// ```
///
/// `len` is the *byte* length in decimal, and it is what stops one message from
/// being read as another: without it `"abc"` and `"ab" ‖ "c"` would hash alike.
///
/// The bytes hashed are the UTF-8 of `message`, as `@provider.sign_message`
/// puts them on the wire, so a signature obtained there verifies against this.
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
