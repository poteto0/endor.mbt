///|
/// The native currency of a chain, as `wallet_addEthereumChain` describes it
/// (EIP-3085): the token used to pay for gas there.
///
/// ```mbt check
/// test "doc: native currency" {
///   let pol = @types.NativeCurrency::new(name="POL", symbol="POL")
///   inspect(
///     pol.to_json().stringify(),
///     content=(
///       #|{"name":"POL","symbol":"POL","decimals":18}
///     ),
///   )
/// }
/// ```
pub struct NativeCurrency {
  priv name : String
  priv symbol : String
  priv decimals : Int
} derive(Eq, Debug)

///|
/// Describe a chain's native currency. `decimals` is 18 for every EVM chain in
/// practice, so it defaults to that.
pub fn NativeCurrency::new(
  name~ : String,
  symbol~ : String,
  decimals? : Int = 18,
) -> NativeCurrency {
  NativeCurrency::{ name, symbol, decimals }
}

///|
/// Encode as the JSON object `wallet_addEthereumChain` expects.
pub fn NativeCurrency::to_json(self : NativeCurrency) -> Json {
  {
    "name": self.name.to_json(),
    "symbol": self.symbol.to_json(),
    "decimals": self.decimals.to_json(),
  }
}

///|
/// Everything a wallet needs in order to add a chain it does not know yet
/// (EIP-3085 / `wallet_addEthereumChain`), which is also what
/// `@provider.switch_or_add_chain` falls back to on a 4902.
///
/// ```mbt check
/// test "doc: chain params" {
///   let params = @types.ChainParams::new(
///     @types.ChainId::polygon(),
///     chain_name="Polygon Mainnet",
///     rpc_urls=["https://polygon-rpc.com"],
///     native_currency=@types.NativeCurrency::new(name="POL", symbol="POL"),
///   )
///   inspect(params.chain_id(), content="ChainId(137)")
/// }
/// ```
pub struct ChainParams {
  priv chain_id : ChainId
  priv chain_name : String
  priv rpc_urls : Array[String]
  priv native_currency : NativeCurrency
  priv block_explorer_urls : Array[String]
} derive(Eq, Debug)

///|
/// Describe a chain. `block_explorer_urls` is optional — an empty list leaves
/// the key out of the request, which is how EIP-3085 spells "no explorer".
pub fn ChainParams::new(
  chain_id : ChainId,
  chain_name~ : String,
  rpc_urls~ : Array[String],
  native_currency~ : NativeCurrency,
  block_explorer_urls? : Array[String] = [],
) -> ChainParams {
  ChainParams::{
    chain_id,
    chain_name,
    rpc_urls,
    native_currency,
    block_explorer_urls,
  }
}

///|
/// The chain these params describe, i.e. the one a wallet ends up on after
/// adding them.
pub fn ChainParams::chain_id(self : ChainParams) -> ChainId {
  self.chain_id
}

///|
/// Encode as the JSON object `wallet_addEthereumChain` expects.
pub fn ChainParams::to_json(self : ChainParams) -> Json {
  let fields = {
    "chainId": self.chain_id.to_json(),
    "chainName": self.chain_name.to_json(),
    "rpcUrls": self.rpc_urls.to_json(),
    "nativeCurrency": self.native_currency.to_json(),
  }
  if !self.block_explorer_urls.is_empty() {
    fields["blockExplorerUrls"] = self.block_explorer_urls.to_json()
  }
  Json::object(fields)
}
