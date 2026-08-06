///|
/// How a transaction offers to pay for its gas.
///
/// The two fee markets are mutually exclusive on the wire: geth rejects a
/// request carrying both `gasPrice` and `maxFeePerGas` / `maxPriorityFeePerGas`
/// with *"both gasPrice and (maxFeePerGas or maxPriorityFeePerGas)
/// specified"*, so this is an enum rather than three optional fields — the
/// invalid combination cannot be spelled.
///
/// `Auto` is what a dapp normally wants: it sends no fee field at all and lets
/// the wallet fill them in. Since London, geth defaults such a request to an
/// EIP-1559 (dynamic-fee, type-`0x02`) transaction — `maxPriorityFeePerGas`
/// from its own tip oracle and `maxFeePerGas` from `2 * baseFee + tip` — and
/// only falls back to a legacy transaction when `gasPrice` is given. `Legacy`
/// therefore means "opt out of EIP-1559", not "the default".
pub(all) enum Fee {
  /// Send no fee field; the wallet decides (EIP-1559 on a London chain).
  Auto
  /// EIP-1559 dynamic fee: a total cap and the tip to the block proposer.
  Eip1559(max_fee_per_gas~ : Wei, max_priority_fee_per_gas~ : Wei)
  /// Pre-EIP-1559 flat `gasPrice`, for chains that never forked to London.
  Legacy(gas_price~ : Wei)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, so the three cases stay
/// the single source of truth for how a fee prints. `estimate_fees` answers
/// with one of them, and which one is the interesting half of the answer.
pub impl Show for Fee with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A transaction to be signed and broadcast: what `eth_sendTransaction` takes.
/// Unlike a `CallRequest`, this one costs the user money and prompts the
/// wallet, so `from` — the account that will sign — is required and comes
/// first.
///
/// `to` is optional because a transaction without one *deploys* the contract
/// whose creation code is `data`. Everything the wallet can work out for
/// itself is left absent: an absent `nonce` lets the wallet order the
/// transaction, an absent `gas` makes it estimate, and an absent fee (`Auto`)
/// lets it price the transaction.
///
/// ```
/// let req = @types.TransactionRequest::new(
///   @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7"),
///   to=@types.Address::from_string("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
///   value=@types.Wei::from_int(1000),
/// )
/// inspect(
///   req.to_json().stringify(),
///   content=(
///     #|{"from":"0x52908400098527886e0f7030069857d2e4169ee7","to":"0x8617e340b3d01fa5f11f306f4090fd50e238070d","value":"0x3e8"}
///   ),
/// )
/// ```
pub struct TransactionRequest {
  priv from : Address
  priv to : Address?
  priv value : Wei?
  priv data : Hex?
  priv gas : Quantity?
  priv nonce : Quantity?
  priv fee : Fee
} derive(Eq, Debug)

///|
/// Describe a transaction sent from `from`. Every other field is optional and
/// left out of the request when absent, which is how the RPC spells
/// "unspecified" — leaving them to the wallet is the normal case. Leaving `to`
/// out is more than that: a transaction with no recipient deploys `data`.
pub fn TransactionRequest::new(
  from : Address,
  to? : Address,
  value? : Wei,
  data? : Hex,
  gas? : Quantity,
  nonce? : Quantity,
  fee? : Fee = Auto,
) -> TransactionRequest {
  TransactionRequest::{ from, to, value, data, gas, nonce, fee }
}

///|
/// Encode as the JSON object `eth_sendTransaction` expects. Absent fields are
/// omitted rather than sent as `null`, and the fee fields are exactly the ones
/// the chosen `Fee` names: `maxFeePerGas` and `maxPriorityFeePerGas` for
/// `Eip1559`, `gasPrice` for `Legacy`, and neither for `Auto`.
pub fn TransactionRequest::to_json(self : TransactionRequest) -> Json {
  let fields = { "from": self.from.to_json() }
  if self.to is Some(to) {
    fields["to"] = to.to_json()
  }
  if self.value is Some(value) {
    fields["value"] = value.to_json()
  }
  if self.data is Some(data) {
    fields["data"] = data.to_json()
  }
  if self.gas is Some(gas) {
    fields["gas"] = gas.to_json()
  }
  if self.nonce is Some(nonce) {
    fields["nonce"] = nonce.to_json()
  }
  match self.fee {
    Auto => ()
    Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~) => {
      fields["maxFeePerGas"] = max_fee_per_gas.to_json()
      fields["maxPriorityFeePerGas"] = max_priority_fee_per_gas.to_json()
    }
    Legacy(gas_price~) => fields["gasPrice"] = gas_price.to_json()
  }
  Json::object(fields)
}
