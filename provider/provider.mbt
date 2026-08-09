///|
/// Abstract interface for a blockchain provider.
/// Like eip1193, http clients
///
/// ```
/// // Any `Provider` can be driven by the typed helpers:
/// async fn count_accounts[P : @provider.Provider](
///   p : P,
/// ) -> Int raise @provider.ProviderError {
///   @provider.accounts(p).length()
/// }
/// ```
pub(open) trait Provider {
  /// Perform a JSON-RPC request. `params` is the raw JSON params value
  /// (typically a JSON array).
  async fn request(Self, method_name~ : String, params~ : Json) -> Json raise ProviderError
}
