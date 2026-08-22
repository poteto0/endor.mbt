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
/// Prompt the wallet behind `provider` for an account, and pair it with the
/// same transport.
///
/// The one call a dapp needs: `eth_requestAccounts` runs here, so the user is
/// asked to connect, and what comes back is a client that signs as whichever
/// account they picked. Wallets gate that prompt behind a user gesture, so
/// call it from a click and not on load.
///
/// A declined prompt arrives as `Provider(UserRejected)`.
///
/// The address is fixed at the moment of connecting. The SDK holds no current
/// account, so a user who switches accounts in the extension afterwards is not
/// followed — subscribe to `@provider.on_accounts_changed` and connect again.
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
/// The EIP-1559 pair the node's own estimate names, or `None` if it named no
/// price at all.
///
/// A flat `Legacy` price becomes the pair that prices the same: the cap is that
/// price and so is the tip, so `base + min(tip, cap - base)` is that price for
/// every base fee at or under it. The transaction pays exactly what the node
/// quoted, whatever the base fee turns out to be.
///
/// Translating rather than refusing, because `estimate_fees` answering `Legacy`
/// is not the claim that the chain has no EIP-1559: it answers that for a head
/// block naming no base fee *or* naming a zero one, and a zero base fee is an
/// ordinary development chain — anvil and hardhat both run that way. On a chain
/// that really did not fork to London the node rejects the type-`0x02`
/// envelope, which is its answer to give and not this layer's to guess.
///
/// A `Legacy` the *caller* named is a different statement and is not translated
/// — see `prepare`.
fn estimated_pair(fee : @types.Fee) -> (@types.Wei, @types.Wei)? {
  match fee {
    Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~) =>
      Some((max_fee_per_gas, max_priority_fee_per_gas))
    Legacy(gas_price~) => Some((gas_price, gas_price))
    Auto => None
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
/// The chain id, the nonce, the fees and the gas all come from the node, so
/// this is a round trip even for an account that signs locally — a signature
/// commits to those numbers, and only the node knows them. Anything passed in
/// is used as given and not asked about.
///
/// Gas is estimated by calling the transaction against the current state,
/// which needs a recipient; a contract creation has to say its own `gas`.
///
/// The fee comes out as the EIP-1559 pair, since that is the only shape a
/// transaction this SDK signs can carry. A `Legacy` fee is therefore refused
/// here — it is a request for a transaction format this path does not build,
/// and `send` is the call that can honour it. A `Legacy` price that
/// `estimate_fees` answered is a different thing and is used: see
/// `estimated_pair`.
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
    Some(Eip1559(max_fee_per_gas~, max_priority_fee_per_gas~)) =>
      Some((max_fee_per_gas, max_priority_fee_per_gas))
    // `Legacy` is the caller opting out of EIP-1559, and opting out is the one
    // thing this path cannot do: what it builds is a type-`0x02` envelope or
    // nothing. Pricing a 1559 transaction off it would answer a request for one
    // transaction format with another.
    Some(Legacy(_)) =>
      raise Incomplete(
        "only an EIP-1559 fee can be signed here; a wallet can send a legacy transaction, so hand it one with send(fee=Legacy(..))",
      )
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
        Some(pair) => Ok(Some(pair))
        None =>
          Ok(estimated_pair(@provider.estimate_fees(self.provider))) catch {
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
  // so this is a node that named no fee at all.
  guard _or_raise(priced) is Some((max_fee_per_gas, max_priority_fee_per_gas)) else {
    raise Incomplete("the node named no gas price")
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
/// Send in one call, for the common case where the caller has nothing to say
/// about the nonce, the fees or the gas.
///
/// Whatever is left out is filled in by whoever is going to sign. For an
/// account that holds its key that means this SDK, so the call goes through
/// `prepare` and every field is pinned off the node first. For an account
/// behind a wallet it means the wallet: what is left out is left out, and the
/// request goes over as it stands.
///
/// That second path is not `prepare`: pinning would spend a round trip each on
/// a chain id the request cannot carry and on numbers the wallet is about to
/// decide again, and it would force the EIP-1559 pair on a chain the wallet
/// could have priced either way. A `Legacy` fee reaches a wallet intact and is
/// sent as one.
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
