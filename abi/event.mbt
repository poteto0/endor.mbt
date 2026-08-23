///|
/// One parameter of an event, as its ABI declares it: the type, and whether
/// Solidity's `indexed` put it in the log's `topics` instead of its `data`.
///
/// An event's parameters are split across two places by the declaration that
/// names them, and nothing on the wire says which half a value came from, so
/// the flag has to travel with the type for a log to be readable at all.
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
/// An event declaration with everything reading a log needs already worked out:
/// the canonical signature, the `topics[0]` it hashes to, and which parameters
/// `data` holds.
///
/// None of that depends on the log, so build this once outside the loop that
/// reads a receipt's logs or a range scan's.
///
/// ```
/// let transfer = @abi.Event::new(
///   name="Transfer",
///   params=[
///     { ty: Address, indexed: true },
///     { ty: Address, indexed: true },
///     { ty: Uint(256), indexed: false },
///   ],
/// )
/// for log in receipt.logs {
///   let args = transfer.decode_log(topics=log.topics, data=log.data)
/// }
/// ```
pub struct Event {
  /// The canonical signature, `Transfer(address,address,uint256)`.
  signature : String
  /// `keccak256` of that signature — the `topics[0]` every log of this event
  /// carries, hashed once here.
  topic0 : @types.Hex
  /// The parameters as declared, in declaration order.
  params : Array[EventParam]
  /// Just the non-indexed ones' types: the block `data` actually holds.
  in_data : Array[AbiType]
  /// How many topics after the first a log of this event must carry.
  indexed : Int
}

///|
pub impl Show for Event with fn output(self, logger) {
  logger.write_string(self.signature)
}

///|
/// Work out a declaration's signature, topic and parameter split, once.
pub fn Event::new(
  name~ : String,
  params~ : Array[EventParam],
) -> Event raise AbiError {
  // the signature is every parameter, indexed or not, while `data` holds only
  // the ones that are not — so both lists come out of one walk
  let declared = []
  let in_data = []
  for p in params {
    declared.push(p.ty)
    if !p.indexed {
      in_data.push(p.ty)
    }
  }
  let signature = signature(name~, inputs=declared)
  {
    signature,
    topic0: event_topic(signature),
    params,
    in_data,
    indexed: params.length() - in_data.length(),
  }
}

///|
/// Read a log back as the arguments the event was emitted with, in declaration
/// order. `indexed` parameters are the topics after the first, and `topics[0]`
/// is checked against the event's own signature hash.
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
/// The convenience spelling, hashing the signature per call; for a batch build
/// an `Event` once. Indexed dynamic types and anonymous events are on the site.
pub fn decode_log(
  name~ : String,
  params~ : Array[EventParam],
  topics~ : Array[@types.Hex],
  data~ : @types.Hex,
) -> Array[AbiValue] raise AbiError {
  Event::new(name~, params~).decode_log(topics~, data~)
}

///|
/// Read a log of this event, against a declaration whose signature and topic
/// are already worked out.
///
/// This is `decode_log` with nothing left to hash: the checks and the answer
/// are exactly the same, and its documentation describes both.
pub fn Event::decode_log(
  self : Event,
  topics~ : Array[@types.Hex],
  data~ : @types.Hex,
) -> Array[AbiValue] raise AbiError {
  let sign = self.signature
  guard topics is [first, .. indexed_topics] else {
    raise InvalidData("`\{sign}`: the log carries no topics at all")
  }
  guard first == self.topic0 else {
    raise InvalidData(
      "`\{sign}`: topics[0] is \{first}, which is another event",
    )
  }
  guard indexed_topics.length() == self.indexed else {
    raise InvalidData(
      "`\{sign}`: \{self.indexed} indexed parameters, but the log carries \{indexed_topics.length()} topics after the first",
    )
  }
  // the non-indexed parameters are one ABI block of their own, laid out as if
  // they were the event's only parameters
  let rest = decode(self.in_data, data)
  let out = []
  let mut topic = 0
  let mut plain = 0
  for p in self.params {
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
    // an indexed value type sits in its topic exactly as it would in a word of
    // `data`, so this is the same reader
    _decode_value(t, topic.digits_view(), 0)
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
