///|
/// The grammar `abi/codegen` writes source against and `eips/eip712` hashes
/// against: what may sit in a name, and — the point of asking — what may not.
test "is_solidity_ident accepts identifiers and nothing else" {
  inspect(@codec.is_solidity_ident("transferFrom"), content="true")
  inspect(@codec.is_solidity_ident("_x0"), content="true")
  // `$` is Solidity's, and inert everywhere this name is written out
  inspect(@codec.is_solidity_ident("$fee"), content="true")
  inspect(@codec.is_solidity_ident(""), content="false")
  inspect(@codec.is_solidity_ident("0x"), content="false")
  // the characters a signature or an encodeType string is joined with, and a
  // name therefore may not carry
  inspect(@codec.is_solidity_ident("Mail(address to)"), content="false")
  inspect(@codec.is_solidity_ident("to,uint256 amount"), content="false")
  inspect(@codec.is_solidity_ident("Person[]"), content="false")
  // nothing outside ASCII is one, and a name that ends past the BMP still
  // answers rather than reading on
  inspect(@codec.is_solidity_ident("naïve"), content="false")
  inspect(@codec.is_solidity_ident("a🙂"), content="false")
}
