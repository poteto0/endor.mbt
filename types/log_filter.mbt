///|
/// One position of a log filter's `topics`, which is a *set* of values that
/// position may take rather than a single one: a node matches the log when the
/// topic at that index is any of them.
///
/// A position with no constraint at all is spelled `None` in the
/// `Array[Topic?]` a filter carries, not by a `Topic` — which is why this type
/// has no "anything" case.
///
/// ```mbt check
/// test "doc: topic alternatives" {
///   let transfer = @types.Hex::from_string(
///     "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
///   )
///   inspect(
///     @types.Topic::exactly(transfer).to_json().stringify(),
///     content=(
///       #|"0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
///     ),
///   )
/// }
/// ```
pub struct Topic {
  /// The values this position may take, at least one. A single alternative is
  /// sent as the bare hex string a node also accepts, so `exactly` and a
  /// one-element `any_of` produce the same request — they mean the same thing.
  priv alternatives : Array[Hex]
} derive(Eq, Debug)

///|
/// Match this position against exactly `topic`.
pub fn Topic::exactly(topic : Hex) -> Topic raise CodecError {
  Topic::any_of([topic])
}

///|
/// Match this position against any of `topics` — the OR a single topic cannot
/// express, which is how one filter follows several events, or one event from
/// several senders.
///
/// Raises on an empty list: a position that matches nothing is `None` in the
/// filter's `topics`, and an empty set would silently mean the opposite.
pub fn Topic::any_of(topics : Array[Hex]) -> Topic raise CodecError {
  guard !topics.is_empty() else {
    raise InvalidLength("a topic needs at least one alternative")
  }
  for topic in topics {
    guard topic.byte_length() == @codec.WORD_BYTES else {
      raise InvalidLength(
        "a topic is \{@codec.WORD_BYTES} bytes, got \{topic.byte_length()}",
      )
    }
  }
  Topic::{ alternatives: topics }
}

///|
/// Encode as the wire form: the bare hex string for a single alternative, the
/// array for several.
pub fn Topic::to_json(self : Topic) -> Json {
  one_or_many(self.alternatives, Hex::to_json)
}

///|
/// A single value, or the array of them — the shape both `address` and each
/// `topics` position take in an `eth_getLogs` filter. The single case is the
/// common one, so it encodes the one element rather than an array it would then
/// throw away.
fn[T] one_or_many(items : Array[T], to_json : (T) -> Json) -> Json {
  if items is [only] {
    to_json(only)
  } else {
    Json::array(items.map(to_json))
  }
}

///|
/// Which blocks a log search covers: a range, or one block named by its hash.
/// The two are exclusive in the RPC — a filter carrying `blockHash` may carry
/// neither `fromBlock` nor `toBlock` — so they are one field here and the
/// invalid combination cannot be spelled.
priv enum Scope {
  Range(from~ : BlockTag?, to~ : BlockTag?)
  AtBlock(BlockHash)
} derive(Eq, Debug)

///|
/// What logs to search for: the criteria `eth_getLogs` takes.
///
/// Every part is optional and narrows the search: the blocks to look in, the
/// contracts to accept logs from, and what the indexed `topics` must be. A
/// filter that constrains nothing matches every log in the latest block.
///
/// ```mbt check
/// test "doc: log filter json" {
///   let usdc = @types.Address::from_string(
///     "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
///   )
///   let transfer = @types.Hex::from_string(
///     "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
///   )
///   let filter = @types.LogFilter::range(
///     from_block=Number(18000000),
///     address=[usdc],
///     topics=[Some(@types.Topic::exactly(transfer))],
///   )
///   inspect(
///     filter.to_json().stringify(),
///     content=(
///       #|{"fromBlock":"0x112a880","address":"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"]}
///     ),
///   )
/// }
/// ```
pub struct LogFilter {
  priv scope : Scope
  priv address : Array[Address]
  /// One entry per topic position, in order. `None` leaves that position
  /// unconstrained while keeping the ones after it at their own index.
  priv topics : Array[Topic?]
} derive(Eq, Debug)

///|
/// Search a range of blocks. An absent bound is left out of the request, which
/// is how the RPC spells "the latest block" for either end. How wide a range a
/// node will answer is the node's business, and `@provider.logs` says what
/// happens when one refuses.
pub fn LogFilter::range(
  from_block? : BlockTag,
  to_block? : BlockTag,
  address? : Array[Address] = [],
  topics? : Array[Topic?] = [],
) -> LogFilter {
  LogFilter::{ scope: Range(from=from_block, to=to_block), address, topics }
}

///|
/// Search exactly the block with `hash`, reorgs included — the one form that
/// names a block a range cannot, since a dropped block still has its hash and
/// no longer has a height.
pub fn LogFilter::at_block(
  hash : BlockHash,
  address? : Array[Address] = [],
  topics? : Array[Topic?] = [],
) -> LogFilter {
  LogFilter::{ scope: AtBlock(hash), address, topics }
}

///|
/// Encode as the filter object `eth_getLogs` takes. A criterion that constrains
/// nothing is omitted rather than sent as `null`, except inside `topics`, where
/// `null` is what holds a position open.
pub fn LogFilter::to_json(self : LogFilter) -> Json {
  let fields : Map[String, Json] = Map([])
  match self.scope {
    Range(from~, to~) => {
      if from is Some(from) {
        fields["fromBlock"] = from.to_json()
      }
      if to is Some(to) {
        fields["toBlock"] = to.to_json()
      }
    }
    AtBlock(hash) => fields["blockHash"] = hash.to_json()
  }
  if !self.address.is_empty() {
    fields["address"] = one_or_many(self.address, Address::to_json)
  }
  if !self.topics.is_empty() {
    fields["topics"] = Json::array(
      self.topics.map(t => {
        match t {
          Some(topic) => topic.to_json()
          None => Json::null()
        }
      }),
    )
  }
  Json::object(fields)
}
