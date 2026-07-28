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
  invoke_rpc(
    provider,
    method_name="personal_sign",
    params=Json::array([@types.Hex::from_utf8(message).to_json(), who.to_json()]),
    decode=@types.Hex::from_json,
  )
}

///|
/// Ask the wallet to sign an EIP-712 typed-data structure with `who`'s key
/// (`eth_signTypedData_v4`), and return the signature.
///
/// `typed_data` is the `{ types, primaryType, domain, message }` document as
/// `Json`, which the wallet receives as a *string*: v4 takes the document
/// serialized, not as a nested object. There is no typed `TypedData` builder
/// yet, so the caller assembles the document and the wallet — not this SDK —
/// hashes it; nothing here needs keccak256.
///
/// The address comes *first* here, the opposite way round from `sign_message`.
///
/// ```
/// async fn[P : @provider.Provider] sign_permit(
///   p : P,
///   who : @types.Address,
///   permit : Json,
/// ) -> @types.Hex raise @provider.ProviderError {
///   @provider.sign_typed_data(p, who, permit)
/// }
/// ```
pub async fn[P : Provider] sign_typed_data(
  provider : P,
  who : @types.Address,
  typed_data : Json,
) -> @types.Hex raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_signTypedData_v4",
    params=Json::array([who.to_json(), Json::string(typed_data.stringify())]),
    decode=@types.Hex::from_json,
  )
}
