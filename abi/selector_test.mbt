///|
/// `signature`, with a failure reported where it happens: every use below is
/// of a type that exists, so raising would be the test's own bug.
fn sig(name~ : String, inputs~ : Array[@abi.AbiType]) -> String {
  @abi.signature(name~, inputs~) catch {
    e => abort("unexpected error: \{e}")
  }
}

///|
test "signature spells a parameter list the way the ABI hashes it" {
  inspect(
    sig(name="transfer", inputs=[Address, Uint(256)]),
    content="transfer(address,uint256)",
  )
  inspect(sig(name="totalSupply", inputs=[]), content="totalSupply()")
  inspect(
    sig(name="f", inputs=[Uint(256), Array(Uint(32)), FixedBytes(10), Bytes]),
    content="f(uint256,uint32[],bytes10,bytes)",
  )
}

///|
/// The selectors of the two ERC-20 methods every explorer shows, plus the
/// examples the Solidity ABI specification works through.
test "selector is the first four bytes of the signature hash" {
  inspect(@abi.selector("transfer(address,uint256)"), content="0xa9059cbb")
  inspect(@abi.selector("balanceOf(address)"), content="0x70a08231")
  inspect(@abi.selector("baz(uint32,bool)"), content="0xcdcd77c0")
  inspect(@abi.selector("bar(bytes3[2])"), content="0xfce353f6")
  inspect(@abi.selector("sam(bytes,bool,uint256[])"), content="0xa5643bf2")
  inspect(
    @abi.selector("f(uint256,uint32[],bytes10,bytes)"),
    content="0x8be65246",
  )
}

///|
/// `topics[0]` of every ERC-20 transfer ever logged.
test "event_topic is the whole hash, not four bytes of it" {
  inspect(
    @abi.event_topic("Transfer(address,address,uint256)"),
    content="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
  )
  inspect(
    @abi.event_topic("Approval(address,address,uint256)"),
    content="0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925",
  )
}

///|
/// A type that cannot exist has no signature, so it never reaches `keccak256`:
/// a selector hashed from `uint7(…)` would be one no contract answers to.
test "an impossible type is refused rather than hashed" {
  inspect(
    refused(() => @abi.signature(name="f", inputs=[Uint(7)]) |> ignore),
    content=(
      #|InvalidAbiType("uint7: width must be a multiple of 8 in 8..=256")
    ),
  )
  inspect(
    refused(() => @abi.signature(name="f", inputs=[FixedBytes(33)]) |> ignore),
    content=(
      #|InvalidAbiType("bytes33: size must be in 1..=32")
    ),
  )
}

///|
test "encode_call is the selector followed by the arguments" {
  let data = @abi.encode_call(name="transfer", inputs=[Address, Uint(256)], args=[
    Address(dead()),
    Uint(1000000000000000000N),
  ]) catch {
    e => abort("unexpected error: \{e}")
  }
  inspect(
    data,
    content="0xa9059cbb" +
      "000000000000000000000000000000000000000000000000000000000000dead" +
      "0000000000000000000000000000000000000000000000000de0b6b3a7640000",
  )
}
