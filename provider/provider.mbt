///|
/// The EIP-1193 provider abstraction. A provider performs a single JSON-RPC
/// call given a method name and a JSON parameter value (usually a JSON array),
/// returning the decoded JSON result or raising a `ProviderError`.
///
/// The method is `async`: the browser implementation (`BrowserProvider`) awaits
/// the underlying JS Promise, while the in-memory `MockProvider` used by tests
/// resolves immediately. The typed RPC layer above is therefore fully testable
/// without a browser.
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
