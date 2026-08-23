///|
/// Ask the wallet to sign `message` with `who`'s key (`personal_sign`), and
/// return the signature.
///
/// The wallet prefixes it the EIP-191 way before hashing, which keeps a
/// signature produced here from ever being a valid transaction. The parameter
/// pair is `[message, address]`, the opposite way round from v4 typed data.
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
/// `personal_sign` puts the message on the wire as hex either way; this is for a
/// nonce or a hash that was never a string. A wallet shows it as hex, so prefer
/// `sign_message` wherever the message really is text.
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
