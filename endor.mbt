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
  type Fee,
  type TxHash,
  type BlockHash,
  type Block,
  type TransactionReceipt,
  type ReceiptStatus,
  type Log,
  type ChainParams,
  type NativeCurrency,
  type CodecError,
  type AbiError,
  type AbiType,
  type AbiValue,
}

///|
/// EIP-712 typed data lives in its own package — the document, its validation
/// and the digest a wallet signs are one subject, and only `sign_typed_data`
/// needs them — but a caller spells the types `@endor.TypedData` as before.
pub using @eip712 {type TypedData, type TypedDataDomain, type TypedDataField}
