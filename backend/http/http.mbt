///|
/// The same node the Anvil backend runs against, reached over plain HTTP
/// instead of through an injected wallet. An implementation detail of `on`,
/// which reads the URL once and hands it to both the protocol and the
/// transport.
priv struct Http {
  url : String
}

///|
impl @backend.Backend for Http with fn name(_) {
  "http"
}

///|
/// The same `ENDOR_E2E_RPC_URL` the Anvil backend reads: one node, two ways in.
impl @backend.Backend for Http with fn endpoint(self) {
  self.url
}

///|
/// Nothing to install — which is the claim this backend exists to prove. An
/// HTTP transport needs no `globalThis.ethereum` and therefore no shim: it is
/// the URL and nothing else.
impl @backend.Backend for Http with fn install(_, _) {

}

///|
/// Run `body` against an `HttpProvider` over `fetch`, or skip when
/// `ENDOR_E2E_RPC_URL` is unset.
///
/// ```
/// @http.on(provider => {
///   inspect(@provider.chain_id(provider), content="ChainId(31337)")
/// })
/// ```
pub async fn on(
  body : async (@rpc.HttpProvider[@endpoint.Endpoint]) -> Unit,
) -> Unit {
  let url = @env.endpoint()
  @backend.run(Http::{ url, }, () => body(@endpoint.at(url)))
}
