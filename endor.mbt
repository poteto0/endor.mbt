///|
/// Re-export the domain types from `@endor/types` so callers can spell them as
/// `@endor.Address`, `@endor.ChainId`, etc.
pub using @types {
  type Address,
  type Hex,
  type ChainId,
  type Wei,
  type Quantity,
  type BlockTag,
  type CallRequest,
  type TransactionRequest,
  type UnsignedTransaction,
  type Authorization,
  type SignedAuthorization,
  type Fee,
  type TxHash,
  type BlockHash,
  type Block,
  type Transaction,
  type Inclusion,
  type TransactionReceipt,
  type ReceiptStatus,
  type Log,
  type FeeHistory,
  type LogFilter,
  type Topic,
  type ChainParams,
  type NativeCurrency,
  type CodecError,
  type AbiError,
  type AbiType,
  type AbiValue,
}

///|
/// The two errors a dapp catches first. They are raised a package down, but a
/// caller should not have to import a package to name what it just caught, so
/// the public error surface is `CodecError`, `AbiError`, `ProviderError` and
/// `ContractError`. `JsError` and `CodegenError` / `ConfigError` stay where they
/// are: nothing outside them can catch them.
pub using @provider {type ProviderError}

///|
pub using @contract {type ContractError}

///|
pub using @account {type AccountError}

///|
/// A client is a transport and an account joined, so its error is either of
/// theirs — spelled `@endor.WalletError` for the same reason the other four are.
pub using @wallet {type WalletError}

///|
/// EIP-712 typed data lives in its own package — the document, its validation
/// and the digest a wallet signs are one subject, and only `sign_typed_data`
/// needs them — but a caller spells the types `@endor.TypedData` as before.
pub using @eip712 {type TypedData, type TypedDataDomain, type TypedDataField}
