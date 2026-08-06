///|
/// What `eth_feeHistory` reports about a run of blocks: what each one burned as
/// its base fee, how full each was, and — when percentiles were asked for —
/// what the transactions in it actually tipped.
///
/// This is a value read back off the wire and built by `from_json` alone, so
/// its fields are the answer rather than accessors in front of one.
///
/// The three arrays are aligned and oldest first, `oldest_block` naming the
/// height of their first element — with one exception, stated on the field:
/// `base_fee_per_gas` is one longer than the others.
pub(all) struct FeeHistory {
  /// The height of the oldest block in the range.
  oldest_block : UInt64
  /// The base fee each block burned per gas, oldest first — and **one element
  /// longer than the range**: the last is the base fee of the block *after* the
  /// newest one, which the protocol already fixes from the newest block's
  /// gas usage. That last element is the one a fee for the next block is built
  /// from.
  base_fee_per_gas : Array[Wei]
  /// `gasUsed / gasLimit` of each block, oldest first: how full it was, which
  /// is what moves the base fee up or down for the block after it.
  gas_used_ratio : Array[Double]
  /// For each block, the effective tip paid at each percentile the caller asked
  /// for, in the order it asked for them.
  ///
  /// `None` when no percentile was asked for — a node omits the field rather
  /// than answering with empty lists, and that is not the same fact as an empty
  /// list would be.
  reward : Array[Array[Wei]]?
} derive(Eq, Debug)

///|
pub impl Show for FeeHistory with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object `eth_feeHistory` answers with.
///
/// A node may answer with a *shorter* range than was asked for — it has no
/// blocks before genesis, and it may keep fewer than the caller wanted — so
/// nothing here checks the lengths against a request this type never saw.
pub fn FeeHistory::from_json(j : Json) -> FeeHistory raise CodecError {
  let fields = json_object(j, what="fee history")
  FeeHistory::{
    oldest_block: quantity_field(fields, "oldestBlock", what="fee history"),
    base_fee_per_gas: array_field(
      fields,
      "baseFeePerGas",
      what="fee history",
      Wei::from_json,
    ),
    gas_used_ratio: array_field(
      fields,
      "gasUsedRatio",
      what="fee history",
      json_double,
    ),
    reward: optional_map(fields, "reward", j => {
      json_array_of(j, what="reward", j => {
        json_array_of(j, what="reward", Wei::from_json)
      })
    }),
  }
}
