///|
/// JSON-RPC's "method not found". A node that never implemented a method
/// answers with this; a *provider* that refuses to forward one answers with
/// EIP-1193's `UnsupportedMethod` (4200) instead, so both spellings mean the
/// same thing to `max_priority_fee_per_gas`.
const METHOD_NOT_FOUND : Int = -32601

///|
/// Return the tip the node suggests paying the block proposer
/// (`eth_maxPriorityFeePerGas`), or `None` when the node does not implement the
/// method.
///
/// `None` is not an error and not a zero tip: `eth_maxPriorityFeePerGas` is a
/// geth extension rather than a standardized method, and a node that never
/// implemented it says so with `-32601` (or a provider that will not forward it
/// with EIP-1193's 4200). Every other failure raises as usual, so a `None` here
/// only ever means "ask somewhere else": `fee_history` with a percentile is one
/// such place, and `estimate_fees` takes another (`eth_gasPrice` less the base
/// fee) so that it always has an answer.
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
    UnsupportedMethod => None
    Rpc(code~, ..) if code == METHOD_NOT_FOUND => None
    e => raise e
  }
}

///|
/// Return the base fee, the fullness and — for each percentile asked for — the
/// tip actually paid, over the `block_count` blocks ending at `newest_block`
/// (`eth_feeHistory`).
///
/// `reward_percentiles` are percentiles of the *gas used* in each block, sorted
/// by effective tip: `[50.0]` asks what the transaction paying for the median
/// unit of gas tipped. They must be within 0–100 and ascending, which is what
/// the node requires and what is checked here so the error names the argument
/// rather than coming back as a node's message about a parameter it was handed.
/// Asking for none is allowed and is the cheap form — the answer then carries no
/// `reward` at all.
///
/// The answer may be shorter than `block_count` (a node keeps only so much
/// history) but its `base_fee_per_gas` is always one longer than the rest: see
/// `@types.FeeHistory`.
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
    raise ProviderError::internal(
      "fee_history: block_count must be at least 1, got \{block_count}",
    )
  }
  let mut previous = 0.0
  for percentile in reward_percentiles {
    guard percentile >= previous && percentile <= 100.0 else {
      raise ProviderError::internal(
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
/// **A dapp normally wants `Auto` instead**, which sends no fee field and lets
/// the wallet price the transaction. This is for the cases where the wallet's
/// answer is not the one to send: bidding above the current market during
/// congestion, replacing a stuck transaction, or pricing one as a relayer that
/// has no wallet to ask.
///
/// What it does, and where each number comes from:
///
/// * the base fee is the latest block's `baseFeePerGas`. A chain that never
///   forked to London has none, and some chains keep it at zero — either way
///   there is no EIP-1559 market to price into, so the answer is
///   `Legacy(gas_price=eth_gasPrice)`.
/// * the tip is `eth_maxPriorityFeePerGas`. Where the node does not implement
///   it, the tip is `eth_gasPrice - baseFee`, which is the same quantity: geth
///   builds the price it suggests by adding its tip oracle's answer to the base
///   fee. A price *below* the base fee (the pending base fee having risen since)
///   would make that difference negative, and it is floored at zero rather than
///   wrapped.
/// * the cap is `2 * baseFee + tip`. The doubling is not in EIP-1559 — it is
///   geth's own default for a request that names no cap
///   (`internal/ethapi/transaction_args.go`), and it is here because it is what
///   a wallet would have sent. It covers a base fee rising for six consecutive
///   full blocks, since each may raise it by at most 12.5%.
///
/// The estimate is a snapshot: the base fee moves every block, and a cap that
/// was generous when it was built can still be too low by the time the
/// transaction is mined.
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
  let base_fee = match block_by_number(provider) {
    Some(block) => block.base_fee_per_gas
    None => None
  }
  guard base_fee is Some(base_fee) && base_fee != @types.Wei::zero() else {
    return Legacy(gas_price=gas_price(provider))
  }
  let base = base_fee.to_bigint()
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
