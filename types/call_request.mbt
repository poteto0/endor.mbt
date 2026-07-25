///|
/// What a call asks the node to evaluate: the transaction-shaped object
/// `eth_call` and `eth_estimateGas` take. The node runs it against its state and
/// answers with the return data (or the gas it would need) instead of
/// broadcasting anything, so no signature and no wallet prompt are involved.
///
/// Only `to` is required. `data` is raw calldata — a 4-byte selector followed by
/// ABI-encoded arguments — which callers encode themselves until the contract
/// layer lands; that layer will produce exactly this `Hex`. `from` is what
/// `msg.sender` reads as, which matters for anything permissioned, and `value`
/// is the wei the call pretends to carry.
///
/// ```
/// let req = @types.CallRequest::new(
///   @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7"),
///   data=@types.Hex::from_string("0x70a08231"),
/// )
/// inspect(
///   req.to_json().stringify(),
///   content=(
///     #|{"to":"0x52908400098527886e0f7030069857d2e4169ee7","data":"0x70a08231"}
///   ),
/// )
/// ```
pub struct CallRequest {
  priv to : Address
  priv from : Address?
  priv data : Hex?
  priv value : Wei?
} derive(Eq, Debug)

///|
/// Describe a call to `to`. Every other field is optional and left out of the
/// request when absent, which is how the RPC spells "unspecified" — an absent
/// `from` lets the node pick the sender, an absent `value` means zero.
pub fn CallRequest::new(
  to : Address,
  from? : Address,
  data? : Hex,
  value? : Wei,
) -> CallRequest {
  CallRequest::{ to, from, data, value }
}

///|
/// Encode as the JSON object `eth_call` / `eth_estimateGas` expect. Absent
/// fields are omitted rather than sent as `null`.
pub fn CallRequest::to_json(self : CallRequest) -> Json {
  let fields = { "to": self.to.to_json() }
  if self.from is Some(from) {
    fields["from"] = from.to_json()
  }
  if self.data is Some(data) {
    fields["data"] = data.to_json()
  }
  if self.value is Some(value) {
    fields["value"] = value.to_json()
  }
  Json::object(fields)
}
