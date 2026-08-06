///|
/// What `eth_feeHistory` answers with over two blocks at one percentile. The
/// third `baseFeePerGas` is the block *after* the newest one — the field is
/// always one longer than the range, which is the whole point of the answer.
fn a_fee_history() -> Map[String, Json] {
  {
    "oldestBlock": "0x10".to_json(),
    "baseFeePerGas": Json::array([
      "0x7".to_json(),
      "0x8".to_json(),
      "0x9".to_json(),
    ]),
    "gasUsedRatio": Json::array([Json::number(0.5), Json::number(0.75)]),
    "reward": Json::array([
      Json::array(["0x1".to_json()]),
      Json::array(["0x2".to_json()]),
    ]),
  }
}

///|
test "a fee history decodes its three aligned arrays" {
  let history = @types.FeeHistory::from_json(Json::object(a_fee_history())) catch {
    e => fail("unexpected error \{e}")
  }
  inspect(history.oldest_block, content="16")
  // one longer than the two blocks described: the last is the next block's
  inspect(history.base_fee_per_gas.length(), content="3")
  inspect(history.base_fee_per_gas[2].to_hex(), content="0x9")
  inspect(history.gas_used_ratio[0], content="0.5")
  inspect(history.gas_used_ratio[1], content="0.75")
  guard history.reward is Some(reward) else { fail("expected rewards") }
  inspect(reward[1][0].to_hex(), content="0x2")
}

///|
/// Asking for no percentile is the cheap form of the call, and a node answers
/// it by leaving `reward` out entirely. `None` is that fact; an empty array
/// would be the different claim that every block tipped nothing.
test "a fee history asked for no percentile has no rewards" {
  let fields = a_fee_history()
  fields.remove("reward")
  let history = @types.FeeHistory::from_json(Json::object(fields)) catch {
    e => fail("unexpected error \{e}")
  }
  assert_true(history.reward is None)
}

///|
/// `gasUsedRatio` is the one number on this wire that is a JSON number rather
/// than a hex quantity, so it is the one that can be handed the wrong shape.
test "a ratio that is not a number is refused" {
  let fields = a_fee_history()
  fields["gasUsedRatio"] = Json::array(["0x1".to_json()])
  try @types.FeeHistory::from_json(Json::object(fields)) catch {
    @types.CodecError::InvalidJson(msg) =>
      assert_true(msg.has_prefix("expected a number"))
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a hex string ratio to be rejected")
  }
}

///|
test "a fee history without base fees is refused" {
  let fields = a_fee_history()
  fields.remove("baseFeePerGas")
  try @types.FeeHistory::from_json(Json::object(fields)) catch {
    @types.CodecError::InvalidJson(msg) =>
      assert_true(msg == "fee history has no baseFeePerGas")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a fee history with no base fees to be rejected")
  }
}
