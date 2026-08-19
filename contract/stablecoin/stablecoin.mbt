///|
/// A stablecoin: an ERC-20 token that also lets its holder *sign* what should
/// happen and leaves the transaction to somebody else. That is what USDC, JPYC
/// and the rest of the regulated stablecoins are — an ERC-20 with
/// [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) *transfer with
/// authorization* and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612)
/// *permit* on top — so this preset is `@erc20.Erc20` plus the calls that
/// submit those signatures.
///
/// The split is by who pays: `eips/eip3009` and `eips/eip2612` build the
/// document the *holder* signs and reach no node, this sends the transaction
/// the *submitter* pays for. A dapp doing both halves uses both packages; a
/// relayer that was handed an authorization and a signature uses only this one.
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
  priv contract : @contract.Contract
} derive(Eq, @debug.Debug)

///|
/// Point at a deployed stablecoin.
pub fn Stablecoin::new(address : @types.Address) -> Stablecoin {
  Stablecoin::{
    contract: @contract.Contract::new(address, errors=@erc20.standard_errors()),
  }
}

///|
/// The token's address.
pub fn Stablecoin::address(self : Stablecoin) -> @types.Address {
  self.contract.address()
}

///|
/// The ERC-20 half — `balance_of`, `transfer`, `nonces`, and the rest.
///
/// A stablecoin *is* an ERC-20 and this preset does not repeat its interface:
/// the extension is what is spelled here, and everything a plain token can do
/// is reached through the token itself.
pub fn Stablecoin::token(self : Stablecoin) -> @erc20.Erc20 {
  @erc20.Erc20::new(self.address())
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
    self.contract.call(provider, name="version", outputs=[String]),
    what="version",
  )
}

///|
/// The EIP-712 domain the token verifies signatures under, read off the token
/// itself and checked against the separator it publishes.
///
/// A domain that is not the token's own is the expensive mistake of both
/// standards: the document signs and displays perfectly well and is then
/// rejected on chain, after the user has approved it. So this reads `name()`
/// and `version()` rather than taking them, and then hands the result to
/// `DOMAIN_SEPARATOR()` — which is the token saying yes or no to the whole
/// domain at once, before anybody is asked to sign.
///
/// `version()` is not universal, and a token without it is answered as `"1"` —
/// the guess that is right almost everywhere. It is a guess the separator
/// check either confirms or refuses, which is why guessing is safe here.
///
/// `chain_id` defaults to the one the provider is on, since signing for a chain
/// the caller is not connected to is the rarer half of the pair.
pub async fn[P : @provider.Provider] Stablecoin::domain(
  self : Stablecoin,
  provider : P,
  chain_id? : @types.ChainId,
) -> @eip712.TypedDataDomain raise @contract.ContractError {
  let chain = match chain_id {
    Some(chain) => chain
    None => @provider.chain_id(provider) catch { e => raise @contract.Rpc(e) }
  }
  let token = self.token()
  let name = token.name(provider)
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
  let on_chain = token.domain_separator(provider)
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
  @contract.bool_answer(
    self.contract.call(
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
/// Submit a signed authorization — `transferWithAuthorization(...)`.
///
/// `submitter` is who sends the transaction and pays the gas, and is *not* the
/// account whose units move: that one is `authorization.from()`, and it signed
/// instead of paying. Anybody at all may be the submitter of this form.
///
/// The signature is the holder's over `authorization.transfer_typed_data(...)`
/// — a signature over the *receive* document is a different hash and the token
/// will not take it.
pub async fn[P : @provider.Provider] Stablecoin::transfer_with_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit(
    provider,
    submitter~,
    name="transferWithAuthorization",
    authorization~,
    signature~,
  )
}

///|
/// Submit a signed authorization the recipient claims —
/// `receiveWithAuthorization(...)`.
///
/// The same transfer, except that the token also requires `submitter` to be
/// `authorization.to()`. That is what makes the payment and the recipient's
/// reaction to it one transaction: a stranger cannot land the transfer out of
/// band first and leave the call that meant to carry it failing against a
/// contract that has already been paid.
pub async fn[P : @provider.Provider] Stablecoin::receive_with_authorization(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.submit(
    provider,
    submitter~,
    name="receiveWithAuthorization",
    authorization~,
    signature~,
  )
}

///|
/// Both transfers, which take the same nine arguments under two names.
async fn[P : @provider.Provider] Stablecoin::submit(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  name~ : String,
  authorization~ : @eip3009.Authorization,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.contract.send(
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
      Uint(8),
      FixedBytes(32),
      FixedBytes(32),
    ],
    args=[
      Address(authorization.from()),
      Address(authorization.to()),
      Uint(authorization.value()),
      Uint(authorization.valid_after()),
      Uint(authorization.valid_before()),
      Bytes(authorization.nonce().to_bytes()),
      ..signature_parts(signature),
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
  self.contract.send(
    provider,
    from=submitter,
    name="cancelAuthorization",
    inputs=[Address, FixedBytes(32), Uint(8), FixedBytes(32), FixedBytes(32)],
    args=[
      Address(cancellation.authorizer()),
      Bytes(cancellation.nonce().to_bytes()),
      ..signature_parts(signature),
    ],
  )
}

///|
/// Submit a signed approval — `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)`.
///
/// EIP-2612's half of the same idea: it sets an allowance the way `approve`
/// does, but the owner only signed, so the spender can raise the allowance and
/// spend it in one transaction of their own. The `nonce` the permit was signed
/// against is a counter — `@erc20.Erc20::nonces` — and goes up by one here,
/// which makes a second permit signed against the same one worthless.
pub async fn[P : @provider.Provider] Stablecoin::permit(
  self : Stablecoin,
  provider : P,
  submitter~ : @types.Address,
  permit~ : @eip2612.Permit,
  signature~ : @types.Hex,
) -> @types.TxHash raise @contract.ContractError {
  self.contract.send(
    provider,
    from=submitter,
    name="permit",
    inputs=[
      Address,
      Address,
      Uint(256),
      Uint(256),
      Uint(8),
      FixedBytes(32),
      FixedBytes(32),
    ],
    args=[
      Address(permit.owner()),
      Address(permit.spender()),
      Uint(permit.value()),
      Uint(permit.deadline()),
      ..signature_parts(signature),
    ],
  )
}

///|
/// The `(v, r, s)` triple every one of these calls ends with, split out of the
/// 65 bytes a wallet answers with.
///
/// The split is checked rather than sliced: `r` and `s` in range and `s` the
/// low one of the pair, since the `ecrecover` behind all of these refuses the
/// high form. A malformed signature is therefore refused here, for the price of
/// no transaction, instead of on chain for the price of one.
///
/// `v` is `27` or `28`. A wallet that answers `0` or `1` is spelling the same
/// signature the way a typed transaction does, and is read as such.
fn signature_parts(
  signature : @types.Hex,
) -> Array[@types.AbiValue] raise @contract.ContractError {
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
  [
    Uint(BigInt::from_int(parsed.recovery_id() + V_OFFSET)),
    Bytes(parsed.r()),
    Bytes(parsed.s()),
  ]
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
