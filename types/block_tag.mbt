///|
/// The block a read is answered at, as accepted by the `eth_*` methods that
/// take a block parameter: one of the named tags, or a concrete block number.
///
/// ```
/// inspect(@types.BlockTag::Latest.to_string(), content="latest")
/// inspect(@types.BlockTag::Number(16).to_string(), content="0x10")
/// ```
pub(all) enum BlockTag {
  /// The most recent mined block — the default for every read.
  Latest
  /// The pending block, including transactions not yet mined.
  Pending
  /// The genesis block.
  Earliest
  /// The most recent block considered safe by the consensus layer.
  Safe
  /// The most recent finalized block.
  Finalized
  /// A concrete block number, sent as a hex quantity.
  Number(UInt64)
} derive(Eq, Debug)

///|
/// The wire form: a named tag, or the block number as a minimal `0x`-prefixed
/// hex quantity.
pub fn BlockTag::to_string(self : BlockTag) -> String {
  match self {
    Latest => "latest"
    Pending => "pending"
    Earliest => "earliest"
    Safe => "safe"
    Finalized => "finalized"
    Number(n) => format_quantity(n)
  }
}

///|
/// Parse a wire-form block specifier: one of the named tags, or a
/// `0x`-prefixed block number.
pub fn BlockTag::from_string(s : String) -> BlockTag raise CodecError {
  match s {
    "latest" => Latest
    "pending" => Pending
    "earliest" => Earliest
    "safe" => Safe
    "finalized" => Finalized
    _ => Number(parse_quantity(s, what="block number"))
  }
}

///|
/// Encode as the JSON string the RPC expects.
pub fn BlockTag::to_json(self : BlockTag) -> Json {
  Json::string(self.to_string())
}

///|
/// Decode from a JSON string.
pub fn BlockTag::from_json(j : Json) -> BlockTag raise CodecError {
  match j {
    String(s) => BlockTag::from_string(s)
    _ => raise InvalidJson("expected block tag string")
  }
}

///|
pub impl Show for BlockTag with fn output(self, logger) {
  logger.write_string(self.to_string())
}
