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
}
