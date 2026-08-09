///|
/// A transport and an account, joined: everything needed to write to a chain.
///
/// The two are separate everywhere else in this SDK — `Provider` is how bytes
/// reach a node, `Account` is what holds a key — and they are separate because
/// the pairing is the caller's to choose. A key in this process reading
/// through HTTP is the normal shape for a backend; a browser wallet doing both
/// is the normal shape for a dapp; and a key in this process reading through
/// the browser wallet's transport is a perfectly good third.
///
/// That last one is why the client asks the *account* what it is, and never
/// the transport. "Is this a browser?" is the wrong question — an HTTP
/// endpoint may hold keys and a browser page may hold a local one. The only
/// thing that decides how a transaction goes out is whether the account can
/// hand over signed bytes.
///
/// Reads do not go through here. They need no account, so they stay
/// `@provider.balance(p, …)` and friends, against the same transport.
pub struct WalletClient[P, A] {
  priv provider : P
  priv account : A
}

///|
/// Pair a transport with an account.
///
/// ```
/// async fn[P : @provider.Provider] backend_client(
///   p : P,
///   key : @types.Hex,
/// ) -> @types.Address raise Error {
///   let client = @wallet.WalletClient::new(p, @local.LocalAccount::new(key))
///   client.address()
/// }
/// ```
pub fn[P, A] WalletClient::new(provider : P, account : A) -> WalletClient[P, A] {
  { provider, account }
}

///|
/// The account this client signs as.
pub fn[P, A : @account.Account] WalletClient::address(
  self : WalletClient[P, A],
) -> @types.Address raise WalletError {
  self.account.address() catch {
    e => raise Account(e)
  }
}

///|
/// Fill in everything a transaction needs that the caller did not say.
///
/// The chain id, the nonce, the fees and the gas all come from the node, so
/// this is a round trip even for an account that signs locally — a signature
/// commits to those numbers, and only the node knows them. Anything passed in
/// is used as given and not asked about.
///
/// Gas is estimated by calling the transaction against the current state,
/// which needs a recipient; a contract creation has to say its own `gas`.
///
/// ```
/// async fn[P : @provider.Provider, A : @account.Account] pay(
///   client : @wallet.WalletClient[P, A],
///   to : @types.Address,
/// ) -> @types.TxHash raise @wallet.WalletError {
///   let tx = client.prepare(to~, value=@types.Wei::from_ether("0.1"))
///   client.send_transaction(tx)
/// }
/// ```
pub async fn[P : @provider.Provider, A : @account.Account] WalletClient::prepare(
  self : WalletClient[P, A],
  to? : @types.Address,
  value? : @types.Wei = @types.Wei::zero(),
  data? : @types.Hex = @types.Hex::from_bytes(b""),
  gas? : @types.Quantity,
  nonce? : @types.Quantity,
  fee? : @types.Fee,
) -> @types.UnsignedTransaction raise WalletError {
  let from = self.address()
  let chain_id = @provider.chain_id(self.provider) catch {
    e => raise Provider(e)
  }
  // The pending count, not the latest: two transactions prepared back to back
  // must not both claim the same nonce.
  let nonce = match nonce {
    Some(nonce) => nonce
    None =>
      @types.Quantity::new(
        @provider.transaction_count(self.provider, from, block=Pending) catch {
          e => raise Provider(e)
        },
      )
  }
  let resolved = match fee {
    Some(fee) => fee
    None =>
      @provider.estimate_fees(self.provider) catch {
        e => raise Provider(e)
      }
  }
  // Only the EIP-1559 pair can be signed here. `Auto` means the caller wanted
  // a wallet to decide, and there is no wallet in this path; `Legacy` is a
  // transaction format this SDK does not produce.
  guard resolved is Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~) else {
    raise Incomplete("a signed transaction needs an EIP-1559 fee: \{resolved}")
  }
  let gas = match (gas, to) {
    (Some(gas), _) => gas
    (None, Some(to)) =>
      @provider.estimate_gas(
        self.provider,
        @types.CallRequest::new(to, from~, data~, value~),
      ) catch {
        e => raise Provider(e)
      }
    (None, None) =>
      raise Incomplete("a contract creation has to say its own gas")
  }
  @types.UnsignedTransaction::new(
    chain_id~,
    nonce~,
    max_priority_fee_per_gas~,
    max_fee_per_gas~,
    gas~,
    to?,
    value~,
    data~,
  )
}

///|
/// Send a prepared transaction, whichever way this account can.
///
/// An account that holds its key signs here and the bytes go out as
/// `eth_sendRawTransaction`. An account behind a wallet cannot hand back
/// signed bytes, so the whole transaction is handed over instead and the
/// wallet signs and broadcasts it in one step — the user sees one prompt
/// either way, and the caller sees one hash.
pub async fn[P : @provider.Provider, A : @account.Account] WalletClient::send_transaction(
  self : WalletClient[P, A],
  tx : @types.UnsignedTransaction,
) -> @types.TxHash raise WalletError {
  if self.account.account_type() == @account.JSON_RPC {
    let request = tx.to_request(from=self.address())
    return @provider.send_transaction(self.provider, request) catch {
      e => raise Provider(e)
    }
  }
  let signed = self.account.sign_transaction(tx) catch { e => raise Account(e) }
  @provider.send_raw_transaction(self.provider, signed) catch {
    e => raise Provider(e)
  }
}

///|
/// Prepare and send in one call, for the common case where the caller has
/// nothing to say about the nonce, the fees or the gas.
pub async fn[P : @provider.Provider, A : @account.Account] WalletClient::send(
  self : WalletClient[P, A],
  to? : @types.Address,
  value? : @types.Wei = @types.Wei::zero(),
  data? : @types.Hex = @types.Hex::from_bytes(b""),
  gas? : @types.Quantity,
  nonce? : @types.Quantity,
  fee? : @types.Fee,
) -> @types.TxHash raise WalletError {
  self.send_transaction(self.prepare(to?, value~, data~, gas?, nonce?, fee?))
}

///|
/// A `personal_sign` signature over the EIP-191 prefixed message.
pub async fn[P, A : @account.Account] WalletClient::sign_message(
  self : WalletClient[P, A],
  message : String,
) -> @types.Hex raise WalletError {
  self.account.sign_message(@types.Hex::from_utf8(message)) catch {
    e => raise Account(e)
  }
}

///|
/// The same over bytes that were never text. See
/// `@provider.sign_message_bytes`.
pub async fn[P, A : @account.Account] WalletClient::sign_message_bytes(
  self : WalletClient[P, A],
  message : @types.Hex,
) -> @types.Hex raise WalletError {
  self.account.sign_message(message) catch {
    e => raise Account(e)
  }
}

///|
/// An `eth_signTypedData_v4` signature over the EIP-712 document.
pub async fn[P, A : @account.Account] WalletClient::sign_typed_data(
  self : WalletClient[P, A],
  typed_data : @eip712.TypedData,
) -> @types.Hex raise WalletError {
  self.account.sign_typed_data(typed_data) catch {
    e => raise Account(e)
  }
}
