///|
/// [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612), *permit*: the ERC-20
/// approval, **signed instead of sent**. Where a dapp used to make the user
/// send `approve` and then send the call that spends the allowance — two
/// prompts, two transactions, two fees — the user signs a `Permit` and the
/// spender submits `permit(...)` alongside its own call, as one transaction.
/// USDC carries it, and so does almost every token written since — it is the
/// most widely used signature on Ethereum that costs nothing to make.
///
/// What is signed is an EIP-712 document, so that is all this package builds:
/// a `Permit` becomes a `@eip712.TypedData`, which `@provider.sign_typed_data`
/// sends to a wallet and whose `digest()` is what the token recovers the signer
/// from. Nothing here calls a contract, exactly as in `eips/eip3009` — but a
/// permit needs two things only the token can answer, so unlike EIP-3009 those
/// are read through the ERC-20 preset and passed *in*:
///
/// * `nonce` — `nonces(owner)`, a counter, so a permit is only signable one at
///   a time and reading it stale means signing a permit that cannot be used.
/// * the domain — `DOMAIN_SEPARATOR()`, against which
///   `@eip712.TypedDataDomain::check_separator` compares the domain this
///   package would sign under.
///
/// ```mbt check
/// test "doc: sign an approval" {
///   let permit = Permit::new(
///     owner=@types.Address::from_string("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"),
///     spender=@types.Address::from_string("0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"),
///     value=1000000,
///     nonce=0,
///     deadline=2000000000,
///   )
///   let document = permit.typed_data(
///     domain(
///       name="USD Coin",
///       version="2",
///       chain_id=@types.ChainId::mainnet(),
///       token=@types.Address::from_string(
///         "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
///       ),
///     ),
///   )
///   inspect(document.primary_type(), content="Permit")
/// }
/// ```

///|
/// An approval for `spender` to move up to `value` of `owner`'s units, good
/// until `deadline` and only at `nonce`.
///
/// The three numbers are `BigInt` because that is what `uint256` is — `value`
/// is in the token's own smallest unit, exactly as `@erc20.Erc20`'s amounts
/// are, and `deadline` is seconds since the epoch.
pub struct Permit {
  priv owner : @types.Address
  priv spender : @types.Address
  priv value : BigInt
  priv nonce : BigInt
  priv deadline : BigInt
} derive(Eq, @debug.Debug)

///|
/// Describe an approval.
///
/// The `nonce` is a **counter**, not the 32 random bytes an EIP-3009
/// authorization carries: it is `nonces(owner)` on the token, it goes up by one
/// each time a permit is used, and a permit signed against a nonce that has
/// already been spent is dead. So only one permit per owner can be in flight,
/// and the value has to be read from the token rather than drawn — see
/// `@erc20.Erc20::nonces`.
///
/// `deadline` has no default. `type(uint256).max` is how the standard spells
/// "never expires", and passing it says that was meant; a signature nobody may
/// submit next year is worth having to spell.
///
/// The widths are checked here as well as by `@eip712.TypedData::new`, which
/// checks every message against the type it declares. That is deliberate: a
/// permit is a value a caller *builds*, so it is refused where it is spelled,
/// and the submitter's path reads the members straight back out through the
/// accessors without a document ever being built.
pub fn Permit::new(
  owner~ : @types.Address,
  spender~ : @types.Address,
  value~ : BigInt,
  nonce~ : BigInt,
  deadline~ : BigInt,
) -> Permit raise @types.CodecError {
  check_uint256(value, what="value")
  check_uint256(nonce, what="nonce")
  check_uint256(deadline, what="deadline")
  Permit::{ owner, spender, value, nonce, deadline }
}

///|
/// Whose units are being approved.
pub fn Permit::owner(self : Permit) -> @types.Address {
  self.owner
}

///|
/// Who may move them.
pub fn Permit::spender(self : Permit) -> @types.Address {
  self.spender
}

///|
/// How many units, in the token's own smallest unit.
pub fn Permit::value(self : Permit) -> BigInt {
  self.value
}

///|
/// The owner's counter this permit is signed against.
pub fn Permit::nonce(self : Permit) -> BigInt {
  self.nonce
}

///|
/// The second after which the token refuses it.
pub fn Permit::deadline(self : Permit) -> BigInt {
  self.deadline
}

///|
/// The `message` half of the document: the five members, spelled as EIP-712
/// wants them. The numbers go out as decimal strings, since a `uint256` runs
/// well past what a JSON number holds exactly.
fn Permit::to_json(self : Permit) -> Json {
  {
    "owner": self.owner.to_json(),
    "spender": self.spender.to_json(),
    "value": self.value.to_string().to_json(),
    "nonce": self.nonce.to_string().to_json(),
    "deadline": self.deadline.to_string().to_json(),
  }
}

///|
/// The document the owner signs — `Permit(address owner,address spender,uint256
/// value,uint256 nonce,uint256 deadline)`, the one shape EIP-2612 defines.
///
/// A token with a *different* permit — DAI's, which takes `(holder, spender,
/// nonce, expiry, allowed)` and grants all-or-nothing rather than an amount —
/// will reject this signature, since the type name and its members are both in
/// the hash, and no domain check will say so. Compare the token's
/// `PERMIT_TYPEHASH` against `document.type_hash("Permit")` if you may be
/// handed either; building DAI's own document is not this package's.
pub fn Permit::typed_data(
  self : Permit,
  domain : @eip712.TypedDataDomain,
) -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    domain,
    primary_type="Permit",
    types=Map([
      (
        "Permit",
        [
          @eip712.TypedDataField::new("owner", "address"),
          @eip712.TypedDataField::new("spender", "address"),
          @eip712.TypedDataField::new("value", "uint256"),
          @eip712.TypedDataField::new("nonce", "uint256"),
          @eip712.TypedDataField::new("deadline", "uint256"),
        ],
      ),
    ]),
    message=self.to_json(),
  )
}

///|
/// The domain every permit is bound to: the token's own —
/// `@eip712.TypedDataDomain::for_token`, which EIP-3009 binds to as well, named
/// here so a caller reaches for it without knowing that.
///
/// `version` defaults to `"1"`, which is what most tokens say — but **not
/// USDC, which says `"2"`**. So the default is the common case rather than a
/// safe one, and `@eip712.TypedDataDomain::check_separator` against the token's
/// own `DOMAIN_SEPARATOR()` is how you find out which you are holding.
pub fn domain(
  name~ : String,
  version? : String = "1",
  chain_id~ : @types.ChainId,
  token~ : @types.Address,
) -> @eip712.TypedDataDomain raise @types.CodecError {
  @eip712.TypedDataDomain::for_token(name~, version~, chain_id~, token~)
}

///|
fn check_uint256(n : BigInt, what~ : String) -> Unit raise @types.CodecError {
  guard @codec.fits_uint(n, bits=@codec.WORD_BITS) else {
    raise @types.InvalidLength("permit \{what} does not fit uint256: \{n}")
  }
}
