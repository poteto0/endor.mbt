///|
/// One parameter of an event, as its ABI declares it: the type, and whether
/// Solidity's `indexed` put it in the log's `topics` instead of its `data`.
///
/// A function's parameters need no such flag — they are all encoded, in order,
/// into one block. An event's are split across two places by the very
/// declaration that names them, and nothing on the wire says which half a value
/// came from, so the flag has to travel with the type for a log to be readable
/// at all. That is the whole reason this exists next to `AbiType`.
///
/// ```
/// // event Transfer(address indexed from, address indexed to, uint256 value)
/// let params : Array[@abi.EventParam] = [
///   { ty: Address, indexed: true },
///   { ty: Address, indexed: true },
///   { ty: Uint(256), indexed: false },
/// ]
/// ```
pub(all) struct EventParam {
  /// The declared type, exactly as it would be spelled in the signature.
  ty : AbiType
  /// `indexed` — the value is a topic rather than part of `data`.
  indexed : Bool
} derive(Eq, Debug)

///|
pub impl Show for EventParam with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Read a log back as the arguments the event was emitted with, in the order
/// the event declares them.
///
/// This is the read side of an event, and it is not simply `decode` on the
/// log's `data`: `indexed` parameters are not in `data` at all, they are the
/// topics after the first. `decode_log` checks `topics[0]` against the event's
/// own signature hash, reads each remaining topic as the indexed parameter it
/// belongs to, decodes `data` as the rest, and hands back one array in
/// **declaration order** — the order the event was written in, which is the
/// only order a caller can pattern-match against.
///
/// A log of some other event raises rather than being decoded into plausible
/// nonsense: `topics[0]` is what tells one event from another, and a receipt
/// holds the logs of every contract the transaction touched.
///
/// It takes the two fields rather than a `@types.Log` because those two are all
/// there is to decode: a `Log` also carries where the event happened, which is
/// nothing a decoder should have to be handed. `eth_getLogs`' answers and a
/// subscription's payloads reach this the same way a receipt's logs do. The
/// call that does take a `Log` belongs a layer up, where
/// `@erc20.Erc20::decode_transfer` is.
///
/// ```
/// let (from, to, value) = match
///   @abi.decode_log(
///     name="Transfer",
///     params=[
///       { ty: Address, indexed: true },
///       { ty: Address, indexed: true },
///       { ty: Uint(256), indexed: false },
///     ],
///     topics=log.topics,
///     data=log.data,
///   ) {
///   [Address(from), Address(to), Uint(value)] => (from, to, value)
///   _ => abort("unreachable: the types above say otherwise")
/// }
/// ```
///
/// ## An indexed `string`, `bytes`, array or struct comes back as its hash
///
/// A topic is one 32-byte word, and those types do not fit in one. Solidity
/// puts the `keccak256` of the encoded value in the topic instead, so the value
/// itself was never in the log and **cannot be recovered from it** — by anyone,
/// not just by this SDK. Such a parameter is answered as `Bytes` holding those
/// 32 bytes: a caller who has a candidate value can hash it and compare, which
/// is exactly what an indexed dynamic parameter is good for, and is all a log
/// filter ever does with one.
///
/// ## Anonymous events are not decoded
///
/// An `anonymous` event writes no signature hash, so its log has no `topics[0]`
/// to match and its first topic is already an argument. Nothing in the log then
/// says which event it is: passing the wrong parameter list would decode
/// silently into the wrong values instead of raising. `decode_log` therefore
/// always expects `topics[0]` to be the signature hash, and a log of an
/// anonymous event fails that check. Read one with `@abi.decode` on the `data`
/// and the topics by hand, where the assumption is written down as your own.
pub fn decode_log(
  name~ : String,
  params~ : Array[EventParam],
  topics~ : Array[@types.Hex],
  data~ : @types.Hex,
) -> Array[AbiValue] raise AbiError {
  // the signature is every parameter, indexed or not — an event is declared
  // once — while `data` holds only the ones that are not, so both lists come
  // out of the one walk over the declaration
  let declared = []
  let in_data = []
  for p in params {
    declared.push(p.ty)
    if !p.indexed {
      in_data.push(p.ty)
    }
  }
  let indexed = params.length() - in_data.length()
  let signature = signature(name~, inputs=declared)
  guard topics is [first, .. indexed_topics] else {
    raise InvalidData("`\{signature}`: the log carries no topics at all")
  }
  guard first == event_topic(signature) else {
    raise InvalidData(
      "`\{signature}`: topics[0] is \{first}, which is another event",
    )
  }
  guard indexed_topics.length() == indexed else {
    raise InvalidData(
      "`\{signature}`: \{indexed} indexed parameters, but the log carries \{indexed_topics.length()} topics after the first",
    )
  }
  // the non-indexed parameters are one ABI block of their own, laid out as if
  // they were the only parameters the event had — which, as far as `data` is
  // concerned, they are
  let rest = decode(in_data, data)
  let out = []
  let mut topic = 0
  let mut plain = 0
  for p in params {
    if p.indexed {
      out.push(_decode_topic(p.ty, indexed_topics[topic]))
      topic += 1
    } else {
      out.push(rest[plain])
      plain += 1
    }
  }
  out
}

///|
/// One indexed parameter: the value itself when the type fits in a word, and
/// the hash the topic holds instead when it does not.
fn _decode_topic(t : AbiType, topic : @types.Hex) -> AbiValue raise AbiError {
  guard topic.byte_length() == @codec.WORD_BYTES else {
    raise InvalidData(
      "a topic is \{@codec.WORD_BYTES} bytes, and this one is \{topic.byte_length()}",
    )
  }
  if _is_hashed_when_indexed(t) {
    Bytes(topic.to_bytes())
  } else {
    // a value type indexed is encoded into the topic exactly as it would be
    // encoded into a word of `data`, so this is the same reader
    _decode_value(t, topic.digits(), 0)
  }
}

///|
/// Whether `indexed` hashes this type rather than storing it.
///
/// The line is not `is_dynamic`: a struct of two `uint256`s is static and still
/// hashed, because what Solidity stores in a topic is the value of an
/// *elementary* type and the hash of everything else.
fn _is_hashed_when_indexed(t : AbiType) -> Bool {
  match t {
    Bytes | String | Array(_) | FixedArray(_, _) | Tuple(_) => true
    _ => false
  }
}
