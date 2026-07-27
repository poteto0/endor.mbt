///|
/// Return the receipt of `tx_hash`, or `None` when there is none yet
/// (`eth_getTransactionReceipt`).
///
/// `None` is not an error: a transaction that has been broadcast but not mined
/// has no receipt, and neither has one the mempool dropped. Telling those two
/// apart takes waiting, which is what `wait_for_receipt` does.
///
/// ```
/// async fn[P : @provider.Provider] mined(
///   p : P,
///   hash : @types.TxHash,
/// ) -> Bool raise @provider.ProviderError {
///   @provider.transaction_receipt(p, hash) is Some(_)
/// }
/// ```
pub async fn[P : Provider] transaction_receipt(
  provider : P,
  tx_hash : @types.TxHash,
) -> @types.TransactionReceipt? raise ProviderError {
  invoke_rpc(
    provider,
    method_name="eth_getTransactionReceipt",
    params=Json::array([tx_hash.to_json()]),
    decode=j => decode_optional(j, @types.TransactionReceipt::from_json),
  )
}

///|
/// Poll until `tx_hash` has a receipt with `confirmations` confirmations, and
/// return it. This is the other half of `send_transaction`: the hash it answers
/// with says the transaction was broadcast, and this says it was mined.
///
/// A receipt in the head block counts as one confirmation, so the default
/// `confirmations=1` returns as soon as the transaction is mined at all. Ask for
/// more to wait out the reorgs that can still take it back out; asking for
/// fewer than one is a caller error and is raised rather than rounded up.
///
/// Both remaining knobs are milliseconds: `timeout` is how long the wait may
/// take in total, `poll_interval` how long to wait between polls.
///
/// Running out of time raises `Timeout`, which is deliberately not the same
/// answer as `transaction_receipt`'s `None`: `None` says the node has no
/// receipt *right now*, `Timeout` says it still had none after being asked for
/// as long as the caller allowed. A transaction that reverted has a receipt and
/// so returns normally, with `status` set to `Reverted` — check it rather than
/// reading a successful return as a successful transaction.
///
/// ```
/// async fn[P : @provider.Provider] confirm(
///   p : P,
///   hash : @types.TxHash,
/// ) -> Bool raise @provider.ProviderError {
///   let receipt = @provider.wait_for_receipt(p, hash, confirmations=2)
///   receipt.status is Success
/// }
/// ```
pub async fn[P : Provider] wait_for_receipt(
  provider : P,
  tx_hash : @types.TxHash,
  confirmations? : Int = 1,
  timeout? : Int = 60_000,
  poll_interval? : Int = 1_000,
) -> @types.TransactionReceipt raise ProviderError {
  // fewer than one confirmation is not a weaker wait, it is no wait at all —
  // and a negative one, converted unsigned, would be a wait for a height the
  // chain never reaches. Neither is what any caller meant, so neither is
  // silently corrected.
  guard confirmations >= 1 else {
    raise ProviderError::internal(
      "wait_for_receipt: confirmations must be at least 1, got \{confirmations}",
    )
  }
  let wanted = confirmations.to_uint64()
  let deadline = @async.now() + timeout.to_int64()
  // a receipt does not change once it exists, so it is fetched once and the
  // rest of the wait is a question about the head alone
  let receipt = for ;; {
    if transaction_receipt(provider, tx_hash) is Some(receipt) {
      break receipt
    }
    guard poll_again(deadline, poll_interval) else {
      raise Timeout("transaction \{tx_hash} was not mined within \{timeout}ms")
    }
  }
  // the receipt's own block is the first confirmation, so the default wait is
  // over without asking the node anything more
  if wanted > 1 {
    // `head + 1 < number + wanted` rather than a subtraction: both sides are
    // unsigned and a reorg can leave the head *below* the receipt's block
    while block_number(provider) + 1 < receipt.block_number + wanted {
      guard poll_again(deadline, poll_interval) else {
        raise Timeout(
          "transaction \{tx_hash} did not reach \{wanted} confirmations within \{timeout}ms",
        )
      }
    }
  }
  receipt
}

///|
/// Wait one poll interval, or answer `false` once `deadline` has passed. Both
/// halves of the wait run off the same deadline, so `timeout` covers the whole
/// call rather than each half of it.
async fn poll_again(
  deadline : Int64,
  poll_interval : Int,
) -> Bool raise ProviderError {
  let remaining = deadline - @async.now()
  guard remaining > 0 else { return false }
  // never nap past the deadline: the last poll before it should still happen
  let nap = if remaining < poll_interval.to_int64() {
    remaining.to_int()
  } else {
    poll_interval
  }
  @async.sleep(nap) catch {
    e => raise ProviderError::internal("waiting to poll again: \{e}")
  }
  true
}
