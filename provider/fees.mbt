///|
/// Return the tip the node suggests paying the block proposer
/// (`eth_maxPriorityFeePerGas`), or `None` when the node does not implement the
/// method.
///
/// `None` is not an error and not a zero tip — it means "ask somewhere else",
/// which `fee_history` with a percentile is, and which `estimate_fees` does.
///
/// ```
/// async fn[P : @provider.Provider] suggested_tip(
///   p : P,
/// ) -> @types.Wei raise @provider.ProviderError {
///   match @provider.max_priority_fee_per_gas(p) {
///     Some(tip) => tip
///     None => @types.Wei::from_gwei("1")
///   }
/// }
/// ```
pub async fn[P : Provider] max_priority_fee_per_gas(
  provider : P,
) -> @types.Wei? raise ProviderError {
  Some(
    invoke_rpc(
      provider,
      method_name="eth_maxPriorityFeePerGas",
      params=Json::array([]),
      decode=@types.Wei::from_json,
    ),
  ) catch {
    e => if e.is_method_not_found() { None } else { raise e }
  }
}

///|
/// Return the base fee, the fullness and — for each percentile asked for — the
/// tip actually paid, over the `block_count` blocks ending at `newest_block`.
///
/// `reward_percentiles` are percentiles of the *gas used* in each block, sorted
/// by effective tip; they must be within 0–100 and ascending. `base_fee_per_gas`
/// is one longer than the rest.
///
/// ```
/// async fn[P : @provider.Provider] median_tip(
///   p : P,
/// ) -> @types.Wei? raise @provider.ProviderError {
///   let history = @provider.fee_history(p, block_count=1, reward_percentiles=[
///     50.0,
///   ])
///   match history.reward {
///     Some([[tip, ..], ..]) => Some(tip)
///     _ => None
///   }
/// }
/// ```
pub async fn[P : Provider] fee_history(
  provider : P,
  block_count~ : Int,
  newest_block? : @types.BlockTag = Latest,
  reward_percentiles? : Array[Double] = [],
) -> @types.FeeHistory raise ProviderError {
  guard block_count >= 1 else {
    raise InvalidConfig(
      "fee_history: block_count must be at least 1, got \{block_count}",
    )
  }
  let mut previous = 0.0
  for percentile in reward_percentiles {
    guard percentile >= previous && percentile <= 100.0 else {
      raise InvalidConfig(
        "fee_history: reward_percentiles must be ascending and within 0-100, got \{@debug.to_string(reward_percentiles)}",
      )
    }
    previous = percentile
  }
  invoke_rpc(
    provider,
    method_name="eth_feeHistory",
    params=Json::array([
      @types.Quantity::new(block_count.to_uint64()).to_json(),
      newest_block.to_json(),
      Json::array(reward_percentiles.map(p => Json::number(p))),
    ]),
    decode=@types.FeeHistory::from_json,
  )
}

///|
/// Build the `@types.Fee` to send a transaction with right now — the fee fields
/// a wallet would otherwise fill in for itself.
///
/// **A dapp normally wants `Auto` instead.** This is for bidding above the
/// market during congestion, replacing a stuck transaction, or pricing one as a
/// relayer. The cap is geth's own `2 * baseFee + tip`.
///
/// ```
/// async fn[P : @provider.Provider] priced(
///   p : P,
///   from : @types.Address,
///   to : @types.Address,
/// ) -> @types.TransactionRequest raise @provider.ProviderError {
///   @types.TransactionRequest::new(
///     from,
///     to~,
///     value=@types.Wei::from_ether("0.01"),
///     fee=@provider.estimate_fees(p),
///   )
/// }
/// ```
pub async fn[P : Provider] estimate_fees(
  provider : P,
) -> @types.Fee raise ProviderError {
  // off a block rather than out of `fee_history`: a chain with no 1559 market
  // is exactly the one that may not implement `eth_feeHistory` either
  guard block_by_number(provider) is Some(block) &&
    block.base_fee_per_gas is Some(base_fee) &&
    base_fee.to_bigint() is base &&
    base != 0N else {
    return Legacy(gas_price=gas_price(provider))
  }
  let tip = match max_priority_fee_per_gas(provider) {
    Some(tip) => tip.to_bigint()
    None => {
      let price = gas_price(provider).to_bigint()
      if price > base {
        price - base
      } else {
        0N
      }
    }
  }
  Eip1559(
    max_fee_per_gas=@types.Wei::from_bigint(base * 2N + tip),
    max_priority_fee_per_gas=@types.Wei::from_bigint(tip),
  )
}
