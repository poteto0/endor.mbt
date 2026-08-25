///|
/// A transport and an account, joined: everything needed to write to a chain.
///
/// The two are separate everywhere else because the pairing is the caller's to
/// choose. That is why the client asks the *account* what it is and never the
/// transport: what decides how a transaction goes out is whether the account
/// can hand over signed bytes. Reads need no account and do not come here.
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
/// Prompt the wallet behind `provider` for an account, and pair it with the same
/// transport — the one call a dapp needs.
///
/// Wallets gate the prompt behind a user gesture, so call it from a click. The
/// address is fixed at the moment of connecting, so a user who switches accounts
/// afterwards is not followed.
///
/// ```
/// async fn connect_and_pay(
///   to : @types.Address,
/// ) -> @types.TxHash raise Error {
///   let wallet = @browser.BrowserProvider::require()
///   let client = @wallet.WalletClient::connect(wallet)
///   client.send(to~, value=@types.Wei::from_ether("0.01"))
/// }
/// ```
pub async fn[P : @provider.Provider] WalletClient::connect(
  provider : P,
) -> WalletClient[P, JsonRpcAccount[P]] raise WalletError {
  let who = @provider.require_account(provider) catch { e => raise Provider(e) }
  WalletClient::new(provider, JsonRpcAccount::new(provider, who))
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
/// The value a task carried back, or the failure it kept instead.
fn[T] _or_raise(result : Result[T, WalletError]) -> T raise WalletError {
  match result {
    Ok(value) => value
    Err(e) => raise e
  }
}

///|
/// Fill in everything a transaction needs that the caller did not say.
///
/// The chain id, the nonce, the fees and the gas all come from the node, so this
/// is a round trip even for an account that signs locally. Gas is estimated
/// against current state, which needs a recipient. The fee decides the
/// transaction format: an EIP-1559 pair builds a type-`0x02` envelope, a flat
/// `Legacy` price builds an EIP-155 legacy transaction.
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
  let named = match fee {
    Some(Eip1559(_) | Legacy(_)) => fee
    // `Auto`, or nothing at all: the caller left the price open, and on this
    // path there is no wallet to leave it to.
    Some(Auto) | None => None
  }
  guard gas is Some(_) || to is Some(_) else {
    raise Incomplete("a contract creation has to say its own gas")
  }

  let (chain_id, nonce, priced, gas) = @async.with_task_group(group => {
    let chain_id = group.spawn(() => {
      Ok(@provider.chain_id(self.provider)) catch {
        e => Err(Provider(e))
      }
    })
    // if not provided, count tx of pending
    let nonce = group.spawn(() => {
      match nonce {
        Some(nonce) => Ok(nonce)
        None =>
          Ok(
            @types.Quantity::new(
              @provider.transaction_count(self.provider, from, block=Pending),
            ),
          ) catch {
            e => Err(Provider(e))
          }
      }
    })
    let priced = group.spawn(() => {
      match named {
        Some(fee) => Ok(fee)
        None =>
          Ok(@provider.estimate_fees(self.provider)) catch {
            e => Err(Provider(e))
          }
      }
    })
    // estimate gs, if not gas provided
    let gas = group.spawn(() => {
      match (gas, to) {
        (Some(gas), _) => Ok(gas)
        (None, Some(to)) =>
          Ok(
            @provider.estimate_gas(
              self.provider,
              @types.CallRequest::new(to, from~, data~, value~),
            ),
          ) catch {
            e => Err(Provider(e))
          }
        // Ruled out before the group was opened.
        (None, None) =>
          Err(
            Provider(@provider.InvalidConfig("unexpected gas, and to is nil")),
          )
      }
    })
    (chain_id.wait(), nonce.wait(), priced.wait(), gas.wait())
  }) catch {
    // The tasks keep their own failures, so nothing but a cancellation of the
    // group itself gets out this way.
    e =>
      raise Provider(
        @provider.Transport("preparing the transaction was cancelled: \{e}"),
      )
  }
  let chain_id = _or_raise(chain_id)
  let nonce = _or_raise(nonce)
  let gas = _or_raise(gas)
  // `estimate_fees` answers with one of the two priced forms and never `Auto`,
  // so that arm is a node that named no fee at all.
  match _or_raise(priced) {
    Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~) =>
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
    Legacy(gas_price~) =>
      @types.UnsignedTransaction::legacy(
        chain_id~,
        nonce~,
        gas_price~,
        gas~,
        to?,
        value~,
        data~,
      )
    Auto => raise Incomplete("the node named no gas price")
  }
}

///|
/// Send a prepared transaction, whichever way this account can.
///
/// An account that holds its key signs here and the bytes go out as
/// `eth_sendRawTransaction`. An account behind a wallet is handed the whole
/// transaction instead, and signs and broadcasts it in one step.
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
/// Send in one call, for the common case where the caller has nothing to say
/// about the nonce, the fees or the gas.
///
/// Whatever is left out is filled in by whoever is going to sign: through
/// `prepare` for an account holding its key, and by the wallet otherwise —
/// pinning first would decide numbers the wallet is about to decide again.
pub async fn[P : @provider.Provider, A : @account.Account] WalletClient::send(
  self : WalletClient[P, A],
  to? : @types.Address,
  value? : @types.Wei = @types.Wei::zero(),
  data? : @types.Hex = @types.Hex::from_bytes(b""),
  gas? : @types.Quantity,
  nonce? : @types.Quantity,
  fee? : @types.Fee,
) -> @types.TxHash raise WalletError {
  if self.account.account_type() == @account.JSON_RPC {
    let request = @types.TransactionRequest::new(
      self.address(),
      to?,
      value~,
      data~,
      gas?,
      nonce?,
      fee?,
    )
    return @provider.send_transaction(self.provider, request) catch {
      e => raise Provider(e)
    }
  }
  self.send_transaction(self.prepare(to?, value~, data~, gas?, nonce?, fee?))
}

///|
/// A `personal_sign` signature over the EIP-191 prefixed message.
pub async fn[P, A : @account.Account] WalletClient::sign_message(
  self : WalletClient[P, A],
  message : String,
) -> @types.Hex raise WalletError {
  self.sign_message_bytes(@types.Hex::from_utf8(message))
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
