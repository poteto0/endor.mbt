///|
/// Who sends the transaction an authorization travels in, which is the whole
/// of what decides the nonce that authorization is signed for.
///
/// The two cases differ by one, and swapping them raises nothing anywhere: a
/// wrong nonce is still a valid signature by the right account, so the
/// transaction is accepted, mined and successful, and the delegation is simply
/// dropped when the block is built. That is why this is asked for rather than
/// worked out from whether two addresses happen to match.
pub(all) enum Sponsorship {
  /// The delegating account is sending its own delegation. The transaction
  /// consumes a nonce first, so the authorization inside it is signed for the
  /// next one.
  SelfSponsored
  /// This client is paying for another account's delegation. That account's
  /// own nonce, unchanged — the transaction moves the sender's nonce, not the
  /// authority's.
  Sponsored(@types.Address)
} derive(Eq, Debug)

///|
/// Render through the derived `Debug` representation, as the rest of the SDK
/// does.
pub impl Show for Sponsorship with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A transaction's nonce and the nonce an authorization riding in it carries.
///
/// The two are read together because they are one answer: under
/// `SelfSponsored` the second is the first plus one, and a caller that asked
/// for them separately would be asking the node twice for a number that moves.
pub(all) struct Nonces {
  /// What to hand `prepare` as its `nonce`.
  transaction : @types.Quantity
  /// What the authorization is signed for.
  authorization : @types.Quantity
} derive(Eq, Debug)

///|
pub impl Show for Nonces with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The two nonces a delegating transaction from this client needs: its own,
/// and the one an authorization inside it has to carry.
///
/// This is the arithmetic EIP-7702 makes easy to get wrong and impossible to
/// notice — see `Sponsorship` — so it is done here rather than at every call
/// site. Sign the authorization for `authorization`, then pass `transaction`
/// to `prepare` so the transaction takes the nonce this answer assumed.
///
/// ```
/// async fn[P : @provider.Provider, A : @account.Account] my_own_delegation(
///   client : @wallet.WalletClient[P, A],
/// ) -> @types.Quantity raise @wallet.WalletError {
///   client.nonces(SelfSponsored).authorization
/// }
/// ```
pub async fn[P : @provider.Provider, A : @account.Account] WalletClient::nonces(
  self : WalletClient[P, A],
  sponsorship : Sponsorship,
) -> Nonces raise WalletError {
  let from = self.address()
  let transaction = self.pending_count(from)
  let authorization = match sponsorship {
    SelfSponsored => transaction + 1
    Sponsored(authority) => {
      guard authority != from else {
        raise Incomplete(
          "this client is the authority: a delegation it sends itself is SelfSponsored",
        )
      }
      self.pending_count(authority)
    }
  }
  Nonces::{
    transaction: @types.Quantity::new(transaction),
    authorization: @types.Quantity::new(authorization),
  }
}

///|
/// The nonce `who`'s next transaction takes: the count including whatever is
/// already in the mempool, which is what a transaction being built now will be
/// given.
async fn[P : @provider.Provider, A] WalletClient::pending_count(
  self : WalletClient[P, A],
  who : @types.Address,
) -> UInt64 raise WalletError {
  @provider.transaction_count(self.provider, who, block=Pending) catch {
    e => raise Provider(e)
  }
}
