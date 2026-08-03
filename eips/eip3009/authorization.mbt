///|
/// [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009), *Transfer With
/// Authorization*: the token holder signs what is to happen, and **someone
/// else submits it**. The holder therefore needs no ether — the submitter pays
/// the gas — and, because the authorization is keyed by a random `nonce`
/// rather than by a sequence number, several may be in flight at once. This is
/// how USDC, JPYC and most other regulated stablecoins are moved without the
/// sender ever holding the chain's own currency.
///
/// What is signed is an EIP-712 document, so that is all this package builds:
/// an `Authorization` becomes a `@eip712.TypedData`, which
/// `@provider.sign_typed_data` sends to a wallet and whose `digest()` is what a
/// contract will recover the signer from. Nothing here calls a contract —
/// `transferWithAuthorization(...)` is the *submitter's* transaction, and the
/// token preset that sends it is the caller of this package, not part of it.
///
/// ```mbt check
/// test "doc: sign a transfer authorization" {
///   let auth = Authorization::new(
///     from=@types.Address::from_string("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"),
///     to=@types.Address::from_string("0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"),
///     value=1000000,
///     valid_before=2000000000,
///     nonce=@types.Hex::from_string(
///       "0x0000000000000000000000000000000000000000000000000000000000000001",
///     ),
///   )
///   let document = auth.transfer_typed_data(
///     domain(
///       name="USD Coin",
///       chain_id=@types.ChainId::mainnet(),
///       token=@types.Address::from_string(
///         "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
///       ),
///     ),
///   )
///   inspect(document.primary_type(), content="TransferWithAuthorization")
/// }
/// ```

///|
/// An authorization to move `value` units from `from` to `to`, valid only
/// between `valid_after` and `valid_before` and only once, at `nonce`.
///
/// The same value describes both of EIP-3009's transfers; which one it is
/// signed as is chosen when the document is built, by
/// `transfer_typed_data` or `receive_typed_data`, since the two differ in
/// nothing but their type name.
///
/// The three numbers are `BigInt` because that is what `uint256` is — the
/// times are seconds since the epoch, and `value` is in the token's own
/// smallest unit, exactly as `@erc20.Erc20`'s amounts are.
pub struct Authorization {
  priv from : @types.Address
  priv to : @types.Address
  priv value : BigInt
  priv valid_after : BigInt
  priv valid_before : BigInt
  priv nonce : @types.Hex
} derive(Eq, @debug.Debug)

///|
/// Describe an authorization.
///
/// `valid_after` defaults to zero — valid from the moment it is signed — since
/// a window that opens later is the rarer half of the pair. `valid_before` has
/// no default: an authorization that never expires is a liability the caller
/// should have to spell out, and passing a far-future timestamp says it was
/// meant.
///
/// The `nonce` is 32 random bytes and **not** a counter: it is what the token
/// marks as used, so two authorizations signed with the same one are the same
/// authorization, and only the first to be submitted takes effect. Drawing it
/// is the caller's, because randomness is not this package's to own.
pub fn Authorization::new(
  from~ : @types.Address,
  to~ : @types.Address,
  value~ : BigInt,
  valid_after? : BigInt = 0,
  valid_before~ : BigInt,
  nonce~ : @types.Hex,
) -> Authorization raise @types.CodecError {
  check_uint256(value, what="value")
  check_uint256(valid_after, what="validAfter")
  check_uint256(valid_before, what="validBefore")
  guard valid_after < valid_before else {
    raise @types.InvalidJson(
      "authorization is valid between \{valid_after} and \{valid_before}, which is never",
    )
  }
  check_nonce(nonce)
  Authorization::{ from, to, value, valid_after, valid_before, nonce }
}

///|
/// Who the units leave.
pub fn Authorization::from(self : Authorization) -> @types.Address {
  self.from
}

///|
/// Who the units reach.
pub fn Authorization::to(self : Authorization) -> @types.Address {
  self.to
}

///|
/// How many units, in the token's own smallest unit.
pub fn Authorization::value(self : Authorization) -> BigInt {
  self.value
}

///|
/// The second the window opens, exclusive.
pub fn Authorization::valid_after(self : Authorization) -> BigInt {
  self.valid_after
}

///|
/// The second the window closes, exclusive.
pub fn Authorization::valid_before(self : Authorization) -> BigInt {
  self.valid_before
}

///|
/// The 32 bytes the token marks as used.
pub fn Authorization::nonce(self : Authorization) -> @types.Hex {
  self.nonce
}

///|
/// The `message` half of the document: the six members, spelled as EIP-712
/// wants them. The numbers go out as decimal strings, since a `uint256` runs
/// well past what a JSON number holds exactly.
pub fn Authorization::to_json(self : Authorization) -> Json {
  {
    "from": self.from.to_json(),
    "to": self.to.to_json(),
    "value": self.value.to_string().to_json(),
    "validAfter": self.valid_after.to_string().to_json(),
    "validBefore": self.valid_before.to_string().to_json(),
    "nonce": self.nonce.to_json(),
  }
}

///|
/// The document for `TransferWithAuthorization`: **anyone** may submit it once
/// it is signed. The plain form, and the one to reach for unless the recipient
/// is a contract that has to react to being paid.
pub fn Authorization::transfer_typed_data(
  self : Authorization,
  domain : @eip712.TypedDataDomain,
) -> @eip712.TypedData raise @types.CodecError {
  self.typed_data(domain, type_name=TRANSFER_TYPE)
}

///|
/// The document for `ReceiveWithAuthorization`: the same transfer, except that
/// the token also requires the *submitter* to be `to`. That closes the front-
/// running window a plain transfer leaves open — a contract that means to act
/// on the payment cannot have the transfer landed on it by a stranger first,
/// out of band, leaving its own call to fail.
pub fn Authorization::receive_typed_data(
  self : Authorization,
  domain : @eip712.TypedDataDomain,
) -> @eip712.TypedData raise @types.CodecError {
  self.typed_data(domain, type_name=RECEIVE_TYPE)
}

///|
/// Both transfers, which are one struct under two names.
fn Authorization::typed_data(
  self : Authorization,
  domain : @eip712.TypedDataDomain,
  type_name~ : String,
) -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    domain,
    primary_type=type_name,
    types=Map([
      (
        type_name,
        [
          @eip712.TypedDataField::new("from", "address"),
          @eip712.TypedDataField::new("to", "address"),
          @eip712.TypedDataField::new("value", "uint256"),
          @eip712.TypedDataField::new("validAfter", "uint256"),
          @eip712.TypedDataField::new("validBefore", "uint256"),
          @eip712.TypedDataField::new("nonce", "bytes32"),
        ],
      ),
    ]),
    message=self.to_json(),
  )
}

///|
/// An authorization taken back before anyone submitted it: it burns the nonce,
/// so whatever was signed against that nonce can no longer take effect.
///
/// Only the account that signed the authorization may cancel it, which is why
/// this carries an `authorizer` rather than reusing the transfer's `from` —
/// cancelling is a claim about who signed, not about where the units were
/// going.
pub struct CancelAuthorization {
  priv authorizer : @types.Address
  priv nonce : @types.Hex
} derive(Eq, @debug.Debug)

///|
/// Describe a cancellation. The `nonce` is the one the authorization being
/// cancelled was signed with.
pub fn CancelAuthorization::new(
  authorizer~ : @types.Address,
  nonce~ : @types.Hex,
) -> CancelAuthorization raise @types.CodecError {
  check_nonce(nonce)
  CancelAuthorization::{ authorizer, nonce }
}

///|
/// Who signed the authorization being taken back.
pub fn CancelAuthorization::authorizer(
  self : CancelAuthorization,
) -> @types.Address {
  self.authorizer
}

///|
/// The nonce being burnt.
pub fn CancelAuthorization::nonce(self : CancelAuthorization) -> @types.Hex {
  self.nonce
}

///|
/// The `message` half of the document.
pub fn CancelAuthorization::to_json(self : CancelAuthorization) -> Json {
  { "authorizer": self.authorizer.to_json(), "nonce": self.nonce.to_json() }
}

///|
/// The document for `CancelAuthorization`.
pub fn CancelAuthorization::typed_data(
  self : CancelAuthorization,
  domain : @eip712.TypedDataDomain,
) -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    domain,
    primary_type=CANCEL_TYPE,
    types=Map([
      (
        CANCEL_TYPE,
        [
          @eip712.TypedDataField::new("authorizer", "address"),
          @eip712.TypedDataField::new("nonce", "bytes32"),
        ],
      ),
    ]),
    message=self.to_json(),
  )
}

///|
/// The domain every EIP-3009 signature is bound to: the token's own.
///
/// It is spelled here rather than left to the caller because getting it wrong
/// is silent — a document with a domain the token does not recognize signs
/// perfectly well, is displayed perfectly well, and is then rejected on chain.
/// Three of the four fields are fixed by EIP-3009 being a token extension:
/// `verifyingContract` is the token, `chainId` is where it lives, and `version`
/// is almost always `"1"`. Only `name` has to be read off the token — it is
/// `name()`, and it must match byte for byte.
pub fn domain(
  name~ : String,
  version? : String = "1",
  chain_id~ : @types.ChainId,
  token~ : @types.Address,
) -> @eip712.TypedDataDomain raise @types.CodecError {
  @eip712.TypedDataDomain::new(
    name~,
    version~,
    chain_id~,
    verifying_contract=token,
  )
}

///|
const TRANSFER_TYPE : String = "TransferWithAuthorization"

///|
const RECEIVE_TYPE : String = "ReceiveWithAuthorization"

///|
const CANCEL_TYPE : String = "CancelAuthorization"

///|
fn check_uint256(n : BigInt, what~ : String) -> Unit raise @types.CodecError {
  guard @codec.fits_uint(n, bits=@codec.WORD_BITS) else {
    raise @types.InvalidLength(
      "authorization \{what} does not fit uint256: \{n}",
    )
  }
}

///|
fn check_nonce(nonce : @types.Hex) -> Unit raise @types.CodecError {
  guard nonce.byte_length() == @codec.WORD_BYTES else {
    raise @types.InvalidLength("authorization nonce must be 32 bytes: \{nonce}")
  }
}
