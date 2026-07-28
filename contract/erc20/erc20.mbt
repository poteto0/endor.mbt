///|
/// An ERC-20 token contract.
///
/// The interface is fixed, so the types are spelled here once instead of at
/// every call site: this is the whole point of a preset. Amounts are `BigInt`
/// in the token's own smallest unit — `decimals` says where the point goes, and
/// dividing by it is a presentation concern the SDK stays out of, exactly as it
/// does for `Wei`.
///
/// ```
/// async fn[P : @provider.Provider] holdings(
///   p : P,
///   token : @endor.Address,
///   who : @endor.Address,
/// ) -> String raise @contract.ContractError {
///   let token = @contract.Erc20::new(token)
///   let amount = token.balance_of(p, who)
///   "\{amount} \{token.symbol(p)}"
/// }
/// ```
pub struct Erc20 {
  priv contract : @contract.Contract
} derive(Eq, @debug.Debug)

///|
/// Point at a deployed token.
pub fn Erc20::new(address : @types.Address) -> Erc20 {
  Erc20::{ contract: @contract.Contract::new(address) }
}

///|
/// The token's address.
pub fn Erc20::address(self : Erc20) -> @types.Address {
  self.contract.address()
}

///|
/// The token's name — `name()`.
pub async fn[P : @provider.Provider] Erc20::name(
  self : Erc20,
  provider : P,
) -> String raise @contract.ContractError {
  _string_answer(
    self.contract.call(provider, name="name", outputs=[String]),
    what="name",
  )
}

///|
/// The token's ticker — `symbol()`.
pub async fn[P : @provider.Provider] Erc20::symbol(
  self : Erc20,
  provider : P,
) -> String raise @contract.ContractError {
  _string_answer(
    self.contract.call(provider, name="symbol", outputs=[String]),
    what="symbol",
  )
}

///|
/// How many decimal places the token's amounts carry — `decimals()`. 18 for
/// most tokens, 6 for USDC and USDT; it is not safe to assume either.
pub async fn[P : @provider.Provider] Erc20::decimals(
  self : Erc20,
  provider : P,
) -> Int raise @contract.ContractError {
  _uint_answer(
    self.contract.call(provider, name="decimals", outputs=[Uint(8)]),
    what="decimals",
  ).to_int()
}

///|
/// How many units exist — `totalSupply()`.
pub async fn[P : @provider.Provider] Erc20::total_supply(
  self : Erc20,
  provider : P,
) -> BigInt raise @contract.ContractError {
  _uint_answer(
    self.contract.call(provider, name="totalSupply", outputs=[Uint(256)]),
    what="totalSupply",
  )
}

///|
/// How many units `owner` holds — `balanceOf(address)`.
pub async fn[P : @provider.Provider] Erc20::balance_of(
  self : Erc20,
  provider : P,
  owner : @types.Address,
) -> BigInt raise @contract.ContractError {
  _uint_answer(
    self.contract.call(
      provider,
      name="balanceOf",
      inputs=[Address],
      args=[Address(owner)],
      outputs=[Uint(256)],
    ),
    what="balanceOf",
  )
}

///|
/// How much of `owner`'s balance `spender` may still move —
/// `allowance(address,address)`.
pub async fn[P : @provider.Provider] Erc20::allowance(
  self : Erc20,
  provider : P,
  owner~ : @types.Address,
  spender~ : @types.Address,
) -> BigInt raise @contract.ContractError {
  _uint_answer(
    self.contract.call(
      provider,
      name="allowance",
      inputs=[Address, Address],
      args=[Address(owner), Address(spender)],
      outputs=[Uint(256)],
    ),
    what="allowance",
  )
}

///|
/// Move `amount` units from `from` to `to` — `transfer(address,uint256)`.
///
/// It signs, so it prompts. The answer is the transaction's hash: whether the
/// transfer went through is in the receipt, and a token that reverts on an
/// insufficient balance reverts there rather than here.
pub async fn[P : @provider.Provider] Erc20::transfer(
  self : Erc20,
  provider : P,
  from~ : @types.Address,
  to~ : @types.Address,
  amount~ : BigInt,
) -> @types.TxHash raise @contract.ContractError {
  self.contract.send(
    provider,
    from~,
    name="transfer",
    inputs=[Address, Uint(256)],
    args=[Address(to), Uint(amount)],
  )
}

///|
/// Let `spender` move up to `amount` of `from`'s units —
/// `approve(address,uint256)`. The step a dapp takes before a contract can pull
/// tokens on the user's behalf.
pub async fn[P : @provider.Provider] Erc20::approve(
  self : Erc20,
  provider : P,
  from~ : @types.Address,
  spender~ : @types.Address,
  amount~ : BigInt,
) -> @types.TxHash raise @contract.ContractError {
  self.contract.send(
    provider,
    from~,
    name="approve",
    inputs=[Address, Uint(256)],
    args=[Address(spender), Uint(amount)],
  )
}

///|
/// `topics[0]` of the log a transfer writes — `Transfer(address,address,uint256)`.
/// What a receipt's logs are matched against to find the transfers in it.
pub fn Erc20::transfer_topic() -> @types.Hex {
  @abi.event_topic("Transfer(address,address,uint256)")
}

///|
/// The single number a getter answered with.
///
/// A getter whose answer does not decode as one number is an address that is
/// not the token it was taken for — the most likely mistake in this whole
/// package, so it names the getter that was asked.
fn _uint_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> BigInt raise @contract.ContractError {
  guard values is [Uint(n)] else {
    raise Abi(@abi.InvalidData("\{what}() did not answer a number"))
  }
  n
}

///|
/// The single string a getter answered with.
fn _string_answer(
  values : Array[@abi.AbiValue],
  what~ : String,
) -> String raise @contract.ContractError {
  guard values is [String(s)] else {
    raise Abi(@abi.InvalidData("\{what}() did not answer a string"))
  }
  s
}
