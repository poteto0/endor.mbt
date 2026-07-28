///|
test "can get name ob api type" {
  inspect(@abi.AbiType::Uint(256).name(), content="uint256")
  inspect(@abi.AbiType::Int(256).name(), content="int256")
  inspect(@abi.AbiType::Address.name(), content="address")
  inspect(@abi.AbiType::Bool.name(), content="bool")
  inspect(@abi.AbiType::FixedBytes(32).name(), content="bytes32")
  inspect(@abi.AbiType::Bytes.name(), content="bytes")
  inspect(@abi.AbiType::String.name(), content="string")
  inspect(
    @abi.AbiType::Array(@abi.AbiType::Uint(256)).name(),
    content="uint256[]",
  )
  inspect(
    @abi.AbiType::FixedArray(@abi.AbiType::Address, 10).name(),
    content="address[10]",
  )
  inspect(
    @abi.AbiType::Tuple([@abi.AbiType::Uint(256), @abi.AbiType::Bool]).name(),
    content="(uint256,bool)",
  )
}
