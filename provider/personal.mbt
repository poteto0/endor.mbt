///|
/// Ask the wallet to sign `message` with `who`'s key (`personal_sign`), and
/// return the signature.
///
/// The message is signed the EIP-191 way: the wallet prefixes it with
/// `"\x19Ethereum Signed Message:\n" + length` before hashing, which is what
/// keeps a signature produced here from ever being a valid transaction. It goes
/// over the wire as the UTF-8 bytes of `message` in hex, so a wallet shows the
/// user the text they are signing.
///
/// EIP-191 puts the address *second* — the parameter pair is
/// `[message, address]`, the opposite way round from `eth_signTypedData_v4`.
///
/// The user is prompted, so a decline arrives as `UserRejected` (4001), and an
/// account the dapp has not been authorized for as `Unauthorized` (4100).
///
/// ```
/// async fn[P : @provider.Provider] prove_ownership(
///   p : P,
///   who : @types.Address,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.sign_message(p, who, "login to example.com")
/// }
/// ```
pub async fn[P : Provider] sign_message(
  provider : P,
  who : @types.Address,
  message : String,
) -> @types.Hex raise ProviderError {
  sign_message_bytes(provider, who, @types.Hex::from_utf8(message))
}

///|
/// The same call over bytes that are not text.
///
/// `personal_sign` puts the message on the wire as hex either way; this is the
/// one to reach for when what is being signed is a nonce, a hash, or anything
/// else that was never a string. A wallet will show it as hex, so a human is
/// being asked to approve something they cannot read — prefer `sign_message`
/// wherever the message really is text.
///
/// ```
/// async fn[P : @provider.Provider] sign_challenge(
///   p : P,
///   who : @types.Address,
///   challenge : @types.Hex,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.sign_message_bytes(p, who, challenge)
/// }
/// ```
pub async fn[P : Provider] sign_message_bytes(
  provider : P,
  who : @types.Address,
  message : @types.Hex,
) -> @types.Hex raise ProviderError {
  invoke_rpc(
    provider,
    method_name="personal_sign",
    params=Json::array([message.to_json(), who.to_json()]),
    decode=@types.Hex::from_json,
  )
}
