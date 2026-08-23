///|
/// A stablecoin: an ERC-20 that also lets its holder *sign* what should happen
/// and leaves the transaction to somebody else — `@erc20.Erc20` plus the calls
/// that submit EIP-3009 and EIP-2612 signatures. USDC and JPYC are these.
///
/// The split is by who pays: `eips/eip3009` and `eips/eip2612` build the
/// document the *holder* signs, this sends the transaction the *submitter* pays.
///
/// ```
/// async fn[P : @provider.Provider] relay(
///   p : P,
///   token : @endor.Address,
///   relayer : @endor.Address,
///   authorization : @eip3009.Authorization,
///   signature : @endor.Hex,
/// ) -> @endor.TxHash raise @contract.ContractError {
///   @stablecoin.Stablecoin::new(token).transfer_with_authorization(
///     p, submitter=relayer, authorization~, signature~,
///   )
/// }
/// ```
pub struct Stablecoin {
  priv erc20 : @erc20.Erc20
} derive(Eq, @debug.Debug)

///|
/// Point at a deployed stablecoin.
pub fn Stablecoin::new(address : @types.Address) -> Stablecoin {
  Stablecoin::{ erc20: @erc20.Erc20::new(address) }
}

///|
/// The token as an `@erc20.Erc20` — for handing to something that takes one.
/// Every call it answers this answers too. The ERC-20 event helpers are the
/// exception: `transfer_topic()` and `decode_transfer(log)` take no token, so
/// they live only there. EIP-3009's own logs are read here.
pub fn Stablecoin::token(self : Stablecoin) -> @erc20.Erc20 {
  self.erc20
}

///|
/// The token as a plain contract — for a function this preset does not spell.
pub fn Stablecoin::contract(self : Stablecoin) -> @contract.Contract {
  self.erc20.contract()
}

///|
/// The token's address.
pub fn Stablecoin::address(self : Stablecoin) -> @types.Address {
  self.erc20.address()
}

///|
/// The token's name — `name()`. See `@erc20.Erc20::name`.
pub async fn[P : @provider.Provider] Stablecoin::name(
  self : Stablecoin,
  provider : P,
) -> String raise @contract.ContractError {
  self.erc20.name(provider)
}

///|
/// The token's ticker — `symbol()`. See `@erc20.Erc20::symbol`.
pub async fn[P : @provider.Provider] Stablecoin::symbol(
  self : Stablecoin,
  provider : P,
) -> String raise @contract.ContractError {
  self.erc20.symbol(provider)
}

///|
/// How many decimal places the token's amounts carry — `decimals()`. 18 for
/// JPYC, 6 for USDC; it is not safe to assume either. See
/// `@erc20.Erc20::decimals`.
pub async fn[P : @provider.Provider] Stablecoin::decimals(
  self : Stablecoin,
  provider : P,
) -> Int raise @contract.ContractError {
  self.erc20.decimals(provider)
}

///|
/// How many units exist — `totalSupply()`. See `@erc20.Erc20::total_supply`.
pub async fn[P : @provider.Provider] Stablecoin::total_supply(
  self : Stablecoin,
  provider : P,
) -> BigInt raise @contract.ContractError {
  self.erc20.total_supply(provider)
}

///|
/// How many units `owner` holds — `balanceOf(address)`. See
/// `@erc20.Erc20::balance_of`.
pub async fn[P : @provider.Provider] Stablecoin::balance_of(
  self : Stablecoin,
  provider : P,
  owner : @types.Address,
) -> BigInt raise @contract.ContractError {
  self.erc20.balance_of(provider, owner)
}

///|
/// How much of `owner`'s balance `spender` may still move —
/// `allowance(address,address)`. See `@erc20.Erc20::allowance`.
pub async fn[P : @provider.Provider] Stablecoin::allowance(
  self : Stablecoin,
  provider : P,
  owner~ : @types.Address,
  spender~ : @types.Address,
) -> BigInt raise @contract.ContractError {
  self.erc20.allowance(provider, owner~, spender~)
}

///|
/// `owner`'s permit counter — `nonces(address)`. What a `@eip2612.Permit` is
/// signed against and what `permit` spends; see `@erc20.Erc20::nonces`.
pub async fn[P : @provider.Provider] Stablecoin::nonces(
  self : Stablecoin,
  provider : P,
  owner : @types.Address,
) -> BigInt raise @contract.ContractError {
  self.erc20.nonces(provider, owner)
}

///|
/// The EIP-712 domain the token verifies signatures under —
/// `DOMAIN_SEPARATOR()`. The hash on its own; `domain` is the whole domain,
/// already checked against it. See `@erc20.Erc20::domain_separator`.
pub async fn[P : @provider.Provider] Stablecoin::domain_separator(
  self : Stablecoin,
  provider : P,
) -> @types.Hex raise @contract.ContractError {
  self.erc20.domain_separator(provider)
}

///|
/// Move `amount` units from `from` to `to` — `transfer(address,uint256)`.
///
/// The half that pays for itself: `from` signs *and* sends. Its counterpart is
/// `transfer_with_authorization`, where those are two different accounts.
/// See `@erc20.Erc20::transfer`.
pub async fn[P : @provider.Provider] Stablecoin::transfer(
  self : Stablecoin,
  provider : P,
  from~ : @types.Address,
  to~ : @types.Address,
  amount~ : BigInt,
) -> @types.TxHash raise @contract.ContractError {
  self.erc20.transfer(provider, from~, to~, amount~)
}

///|
/// Let `spender` move up to `amount` of `from`'s units —
/// `approve(address,uint256)`. `permit` is the same allowance signed rather
/// than sent. See `@erc20.Erc20::approve`.
pub async fn[P : @provider.Provider] Stablecoin::approve(
  self : Stablecoin,
  provider : P,
  from~ : @types.Address,
  spender~ : @types.Address,
  amount~ : BigInt,
) -> @types.TxHash raise @contract.ContractError {
  self.erc20.approve(provider, from~, spender~, amount~)
}

///|
/// The signing version the token declares — `version()`.
///
/// Part of neither standard, but every implementation descended from Centre's
/// `FiatToken` — which is most of them — carries it, and it is the field of the
/// EIP-712 domain nobody can guess: `"2"` on USDC, `"1"` almost everywhere
/// else.
pub async fn[P : @provider.Provider] Stablecoin::version(
  self : Stablecoin,
  provider : P,
) -> String raise @contract.ContractError {
  @contract.string_answer(
    self.contract().call(provider, name="version", outputs=[String]),
    what="version",
  )
}

///|
/// The EIP-712 domain the token verifies signatures under, read off the token
/// itself and checked against the separator it publishes.
///
/// A domain that is not the token's own signs and displays perfectly well and is
/// then rejected on chain, so this reads `name()` and `version()` and hands the
/// result to `DOMAIN_SEPARATOR()`. A token without `version()` is read as `"1"`.
pub async fn[P : @provider.Provider] Stablecoin::domain(
  self : Stablecoin,
  provider : P,
  chain_id? : @types.ChainId,
) -> @eip712.TypedDataDomain raise @contract.ContractError {
  let chain = match chain_id {
    Some(chain) => chain
    None => @provider.chain_id(provider) catch { e => raise @contract.Rpc(e) }
  }
  let name = self.name(provider)
  let version = self.version(provider) catch { _ => "1" }
  // the token's own domain, which is what EIP-2612 binds to as well — so it is
  // spelled as neither standard's rather than reached for through one of them
  let domain = @eip712.TypedDataDomain::for_token(
    name~,
    version~,
    chain_id=chain,
    token=self.address(),
  ) catch {
    e => raise domain_error(e)
  }
  let on_chain = self.domain_separator(provider)
  domain.check_separator(on_chain~) catch {
    e => raise domain_error(e)
  }
  domain
}

///|
/// Whether the nonce is spent — `authorizationState(address,bytes32)`.
///
/// True once the authorization was submitted *or* cancelled: the token marks
/// the nonce either way, and neither the holder nor a submitter can tell the
/// two apart from here. What it is for is the check before paying for a
/// transaction that would revert.
pub async fn[P : @provider.Provider] Stablecoin::authorization_state(
  self : Stablecoin,
  provider : P,
  authorizer~ : @types.Address,
  nonce~ : @types.Hex,
) -> Bool raise @contract.ContractError {
  let contract = self.contract()
  @contract.bool_answer(
    contract.call(
      provider,
      name="authorizationState",
      inputs=[Address, FixedBytes(32)],
      args=[Address(authorizer), Bytes(nonce.to_bytes())],
      outputs=[Bool],
    ),
    what="authorizationState",
  )
}

///|
/// Submit a signed authorization —
/// `transferWithAuthorization(…,uint8,bytes32,bytes32)`.
///
/// `submitter` sends the transaction and pays the gas, and is *not* the account
/// whose units move — that one is `authorization.from()`. The signature must be
/// over `transfer_typed_data(...)`; the *receive* document is a different hash.
pub async fn[P : @provider.Provider] Stablecoin::transfer_with_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_authorization(
    provider,
    submitter~,
    name="transferWithAuthorization",
    authorization~,
    tail=vrs_tail(signature),
  )
}

///|
/// The same transfer, for a signature a *contract* made —
/// `transferWithAuthorization(…,bytes)`.
///
/// FiatTokenV2_2 added a second spelling that takes the signature as `bytes` and
/// asks a contract signer to vouch for it (EIP-1271). Which form to send is the
/// caller's to say: an older token lacks this selector, and the call reverts.
pub async fn[P : @provider.Provider] Stablecoin::transfer_with_authorization_1271(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_authorization(
    provider,
    submitter~,
    name="transferWithAuthorization",
    authorization~,
    tail=bytes_tail(signature),
  )
}

///|
/// Submit a signed authorization the recipient claims —
/// `receiveWithAuthorization(…,uint8,bytes32,bytes32)`.
///
/// The same transfer, except that the token also requires `submitter` to be
/// `authorization.to()`. That is what makes the payment and the recipient's
/// reaction to it one transaction.
pub async fn[P : @provider.Provider] Stablecoin::receive_with_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_authorization(
    provider,
    submitter~,
    name="receiveWithAuthorization",
    authorization~,
    tail=vrs_tail(signature),
  )
}

///|
/// The same receive, for a signature a contract made —
/// `receiveWithAuthorization(…,bytes)`. See
/// `transfer_with_authorization_1271`: V2_2 and later only.
pub async fn[P : @provider.Provider] Stablecoin::receive_with_authorization_1271(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_authorization(
    provider,
    submitter~,
    name="receiveWithAuthorization",
    authorization~,
    tail=bytes_tail(signature),
  )
}

///|
/// Both transfers under both spellings: the six members of the authorization
/// are the same everywhere, and only the signature after them differs.
async fn[P : @provider.Provider] Stablecoin::submit_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  name~ : String,
  authorization~ : @eip3009.Authorization,
  tail~ : SignatureTail,
) -> @types.TxHash raise @contract.ContractError {
  let contract = self.contract()
  contract.send(
    provider,
    from=submitter,
    name~,
    inputs=[
      Address,
      Address,
      Uint(256),
      Uint(256),
      Uint(256),
      FixedBytes(32),
      ..tail.inputs,
    ],
    args=[
      Address(authorization.from()),
      Address(authorization.to()),
      Uint(authorization.value()),
      Uint(authorization.valid_after()),
      Uint(authorization.valid_before()),
      Bytes(authorization.nonce().to_bytes()),
      ..tail.args,
    ],
  )
}

///|
/// Burn a nonce so what was signed against it can no longer be submitted —
/// `cancelAuthorization(address,bytes32,uint8,bytes32,bytes32)`.
///
/// Unlike the transfer, this one costs the *canceller* gas, and the signature
/// has to be `cancellation.authorizer()`'s: cancelling is a claim about who
/// signed the authorization, so nobody else can take it back.
pub async fn[P : @provider.Provider] Stablecoin::cancel_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  cancellation~ : @eip3009.CancelAuthorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_cancellation(
    provider,
    submitter~,
    cancellation~,
    tail=vrs_tail(signature),
  )
}

///|
/// The same cancellation, for a signature a contract made —
/// `cancelAuthorization(address,bytes32,bytes)`. See
/// `transfer_with_authorization_1271`: V2_2 and later only.
pub async fn[P : @provider.Provider] Stablecoin::cancel_authorization_1271(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  cancellation~ : @eip3009.CancelAuthorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_cancellation(
    provider,
    submitter~,
    cancellation~,
    tail=bytes_tail(signature),
  )
}

///|
/// The cancellation under both spellings.
async fn[P : @provider.Provider] Stablecoin::submit_cancellation(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  cancellation~ : @eip3009.CancelAuthorization,
  tail~ : SignatureTail,
) -> @types.TxHash raise @contract.ContractError {
  let contract = self.contract()
  contract.send(
    provider,
    from=submitter,
    name="cancelAuthorization",
    inputs=[Address, FixedBytes(32), ..tail.inputs],
    args=[
      Address(cancellation.authorizer()),
      Bytes(cancellation.nonce().to_bytes()),
      ..tail.args,
    ],
  )
}

///|
/// `topics[0]` of the log a submitted authorization writes —
/// `AuthorizationUsed(address,bytes32)`. What a receipt's logs are matched
/// against to find which authorizations went through.
pub fn Stablecoin::authorization_used_topic() -> @types.Hex {
  authorization_used.topic0
}

///|
/// One `AuthorizationUsed` log, read back as `(authorizer, nonce)`.
///
/// The nonce is what a submitter cannot get any other way: a relayer that sent
/// several `transferWithAuthorization` at once cannot tell their `Transfer` logs
/// apart. Both parameters are `indexed`, so `data` is empty.
///
/// ```
/// fn burned(
///   receipt : @endor.TransactionReceipt,
///   token : @endor.Address,
/// ) -> Array[(@endor.Address, @endor.Hex)] raise @contract.ContractError {
///   let topic = @stablecoin.Stablecoin::authorization_used_topic()
///   let out = []
///   for log in receipt.logs {
///     if log.address == token && log.topics.get(0) is Some(t) && t == topic {
///       out.push(@stablecoin.Stablecoin::decode_authorization_used(log))
///     }
///   }
///   out
/// }
/// ```
pub fn Stablecoin::decode_authorization_used(
  log : @types.Log,
) -> (@types.Address, @types.Hex) raise @contract.ContractError {
  decode_authorization_log(log, authorization_used)
}

///|
/// `topics[0]` of the log a cancellation writes —
/// `AuthorizationCanceled(address,bytes32)`. One `n` in `Canceled`: the
/// signature is hashed as the token spells it, not as English does.
pub fn Stablecoin::authorization_canceled_topic() -> @types.Hex {
  authorization_canceled.topic0
}

///|
/// One `AuthorizationCanceled` log, read back as `(authorizer, nonce)`.
///
/// See `decode_authorization_used`, whose shape this is. A cancellation writes
/// no `Transfer` beside it, so this log is the only record in the receipt that
/// the nonce is dead rather than pending.
pub fn Stablecoin::decode_authorization_canceled(
  log : @types.Log,
) -> (@types.Address, @types.Hex) raise @contract.ContractError {
  decode_authorization_log(log, authorization_canceled)
}

///|
/// Either of the two logs, against a declaration already worked out.
fn decode_authorization_log(
  log : @types.Log,
  event : @abi.Event,
) -> (@types.Address, @types.Hex) raise @contract.ContractError {
  let values = event.decode_log(topics=log.topics, data=log.data) catch {
    e => raise @contract.Abi(e)
  }
  // unreachable: `decode_log` answers with the declared types, or raises
  guard values is [Address(authorizer), Bytes(nonce)] else {
    raise @contract.Abi(
      @types.InvalidData("\{event} did not decode as its own types"),
    )
  }
  (authorizer, @types.Hex::from_bytes(nonce))
}

///|
/// The two declarations, worked out once rather than per log: the topic and the
/// decoder both read them, so the signature is spelled in one place, and a
/// receipt's worth of logs costs no signature building at all.
let authorization_used : @abi.Event = authorization_event("AuthorizationUsed")

///|
let authorization_canceled : @abi.Event = authorization_event(
  "AuthorizationCanceled",
)

///|
/// EIP-3009 declares the two with the same parameters, both `indexed`, so only
/// the name differs. The `abort` is unreachable: two elementary types.
fn authorization_event(name : String) -> @abi.Event {
  @abi.Event::new(name~, params=[
    { ty: Address, indexed: true },
    { ty: FixedBytes(32), indexed: true },
  ]) catch {
    e => abort("\{name}(address,bytes32) is not an event: \{e}")
  }
}

///|
/// Submit a signed approval — `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`.
///
/// EIP-2612's half of the same idea: it sets an allowance the way `approve`
/// does, but the owner only signed, so the spender can raise the allowance and
/// spend it in one transaction. The `nonce` counter goes up by one here.
pub async fn[P : @provider.Provider] Stablecoin::permit(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  permit~ : @eip2612.Permit,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_permit(provider, submitter~, permit~, tail=vrs_tail(signature))
}

///|
/// The same approval, for a signature a contract made —
/// `permit(address,address,uint256,uint256,bytes)`. See
/// `transfer_with_authorization_1271`: V2_2 and later only.
pub async fn[P : @provider.Provider] Stablecoin::permit_1271(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  permit~ : @eip2612.Permit,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit_permit(provider, submitter~, permit~, tail=bytes_tail(signature))
}

///|
/// The approval under both spellings.
async fn[P : @provider.Provider] Stablecoin::submit_permit(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  permit~ : @eip2612.Permit,
  tail~ : SignatureTail,
) -> @types.TxHash raise @contract.ContractError {
  let contract = self.contract()
  contract.send(
    provider,
    from=submitter,
    name="permit",
    inputs=[Address, Address, Uint(256), Uint(256), ..tail.inputs],
    args=[
      Address(permit.owner()),
      Address(permit.spender()),
      Uint(permit.value()),
      Uint(permit.deadline()),
      ..tail.args,
    ],
  )
}

///|
/// What one of these calls ends with: the signature, and the types it is
/// spelled under. Everything before it is the same in either form.
priv struct SignatureTail {
  inputs : Array[@types.AbiType]
  args : Array[@types.AbiValue]
}

///|
/// The signature as `bytes`, whatever it is — the V2_2 form, where the token
/// checks it itself and a contract's answer is as good as an EOA's. Nothing is
/// validated here because there is nothing to validate against: only the signer
/// knows what shape its own `isValidSignature` takes.
fn bytes_tail(signature : @types.Hex) -> SignatureTail {
  { inputs: [Bytes], args: [Bytes(signature.to_bytes())] }
}

///|
/// The `(v, r, s)` triple the V2 form ends with, split out of the 65 bytes a
/// wallet answers with.
///
/// Checked rather than sliced — `r` and `s` in range, `s` the low one — so a
/// malformed signature is refused for the price of no transaction. `v` is `27`
/// or `28`; a wallet answering `0` or `1` spells it as a typed transaction does.
fn vrs_tail(
  signature : @types.Hex,
) -> SignatureTail raise @contract.ContractError {
  let bytes = signature.to_bytes()
  guard bytes.length() == 65 else {
    raise @contract.Abi(
      @types.InvalidData("signature must be 65 bytes: \{signature}"),
    )
  }
  // nothing in the 65 bytes says which spelling they carry, so the byte itself
  // is what decides: a `v` below the offset is a recovery id already
  let offset = if bytes[64].to_int() < V_OFFSET { 0 } else { V_OFFSET }
  let parsed = @secp256k1.Signature::from_bytes(bytes, v_offset=offset) catch {
    InvalidLength(why) | InvalidKey(why) | InvalidSignature(why) =>
      raise @contract.Abi(@types.InvalidData("signature: \{why}"))
  }
  {
    inputs: [Uint(8), FixedBytes(32), FixedBytes(32)],
    args: [
      Uint(BigInt::from_int(parsed.recovery_id() + V_OFFSET)),
      Bytes(parsed.r()),
      Bytes(parsed.s()),
    ],
  }
}

///|
/// What `ecrecover` wants added to a recovery id: `27` or `28`, the spelling
/// EIP-155 left the signatures a wallet answers with.
const V_OFFSET : Int = 27

///|
/// A domain that does not add up. `ContractError` has no word of its own for
/// it, and `Abi` is the closest: what failed is a value this package built out
/// of what the token answered.
fn domain_error(e : @types.CodecError) -> @contract.ContractError {
  // `message()` is the prose a user is shown; what is wanted here is the
  // detail underneath it, which every variant carries.
  let why = match e {
    InvalidHex(why)
    | InvalidLength(why)
    | InvalidJson(why)
    | InvalidChecksum(why)
    | InvalidDecimal(why)
    | InvalidValue(why) => why
  }
  @contract.Abi(@types.InvalidData(why))
}
