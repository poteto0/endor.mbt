///|
/// The endpoint the end-to-end suite runs against, from `ENDOR_E2E_RPC_URL`
/// (`just e2e` sets it). Empty when unset, and then every test skips — which is
/// what keeps a plain `moon test` hermetic.
///
/// One reader for every backend: the URL is the suite's configuration, and a
/// second reader is a second place for a renamed variable to be missed.
pub fn endpoint() -> String {
  @core_env.get_env_var("ENDOR_E2E_RPC_URL").unwrap_or("")
}
