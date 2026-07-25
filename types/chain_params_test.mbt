///|
test "chain params encode as EIP-3085 json" {
  let polygon = @types.ChainParams::new(
    @types.ChainId::polygon(),
    chain_name="Polygon Mainnet",
    rpc_urls=["https://polygon-rpc.com"],
    native_currency=@types.NativeCurrency::new(name="POL", symbol="POL"),
    block_explorer_urls=["https://polygonscan.com"],
  )
  inspect(
    polygon.to_json().stringify(),
    content=(
      #|{"chainId":"0x89","chainName":"Polygon Mainnet","rpcUrls":["https://polygon-rpc.com"],"nativeCurrency":{"name":"POL","symbol":"POL","decimals":18},"blockExplorerUrls":["https://polygonscan.com"]}
    ),
  )
  inspect(polygon.chain_id(), content="ChainId(137)")
}

///|
/// A chain with no explorer leaves the key out rather than sending an empty
/// array, and `decimals` defaults to the 18 every EVM chain uses.
test "chain params without a block explorer" {
  let anvil = @types.ChainParams::new(
    @types.ChainId::new(31337),
    chain_name="Anvil",
    rpc_urls=["http://127.0.0.1:8545"],
    native_currency=@types.NativeCurrency::new(name="Ether", symbol="ETH"),
  )
  inspect(
    anvil.to_json().stringify(),
    content=(
      #|{"chainId":"0x7a69","chainName":"Anvil","rpcUrls":["http://127.0.0.1:8545"],"nativeCurrency":{"name":"Ether","symbol":"ETH","decimals":18}}
    ),
  )
}
