///|
/// `event Transfer(address indexed from, address indexed to, uint256 value)` —
/// the log every ERC-20 writes, and the case the tests here vary.
fn transfer_params() -> Array[@abi.EventParam] {
  [
    { ty: Address, indexed: true },
    { ty: Address, indexed: true },
    { ty: Uint(256), indexed: false },
  ]
}

///|
/// A topic, from the digits that are not padding.
fn topic(digits : String) -> @types.Hex {
  @types.Hex::from_string("0x" + word(digits)) catch {
    e => abort("bad test topic: \{e}")
  }
}

///|
/// A log decoded, as text — the same shape as `decoded`, and for the same
/// reason: what these tests are about is what comes out.
fn decoded_log(
  name~ : String,
  params~ : Array[@abi.EventParam],
  topics~ : Array[@types.Hex],
  data~ : String,
) -> String {
  let data = @types.Hex::from_string(data) catch {
    e => abort("bad test data: \{e}")
  }
  let values = @abi.decode_log(name~, params~, topics~, data~) catch {
    e => abort("unexpected error: \{e}")
  }
  @debug.to_string(values)
}

///|
/// The error a log raised, as text — `refused` with the hex parsed, since not
/// raising is as much an answer here as it is there.
fn log_refused(
  name~ : String,
  params~ : Array[@abi.EventParam],
  topics~ : Array[@types.Hex],
  data~ : String,
) -> String {
  let data = @types.Hex::from_string(data) catch {
    e => abort("bad test data: \{e}")
  }
  refused(() => @abi.decode_log(name~, params~, topics~, data~) |> ignore)
}

///|
/// The whole point: a value that was in `topics` and one that was in `data`
/// come back side by side, in the order the event declares them.
test "decode_log reassembles topics and data in declaration order" {
  inspect(
    decoded_log(
      name="Transfer",
      params=transfer_params(),
      topics=[
        @abi.event_topic("Transfer(address,address,uint256)"),
        topic("dead"),
        topic("beef"),
      ],
      data="0x" + word("2a"),
    ),
    content=(
      #|[
      #|  Address("0x000000000000000000000000000000000000dead"),
      #|  Address("0x000000000000000000000000000000000000beef"),
      #|  Uint(42),
      #|]
    ),
  )
}

///|
/// A receipt holds the logs of every contract the transaction touched, so
/// `topics[0]` is the only thing that says this log is the event asked for.
test "decode_log refuses a log of another event" {
  inspect(
    log_refused(
      name="Transfer",
      params=transfer_params(),
      topics=[
        @abi.event_topic("Approval(address,address,uint256)"),
        topic("dead"),
        topic("beef"),
      ],
      data="0x" + word("2a"),
    ),
    content=(
      #|InvalidData("`Transfer(address,address,uint256)`: topics[0] is 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925, which is another event")
    ),
  )
}

///|
test "decode_log counts the topics the event declares" {
  inspect(
    log_refused(
      name="Transfer",
      params=transfer_params(),
      topics=[
        @abi.event_topic("Transfer(address,address,uint256)"),
        topic("dead"),
      ],
      data="0x" + word("2a"),
    ),
    content=(
      #|InvalidData("`Transfer(address,address,uint256)`: 2 indexed parameters, but the log carries 1 topics after the first")
    ),
  )
}

///|
/// An anonymous event's log arrives here as a log with one topic too few — or,
/// as below, with none at all. It is refused rather than guessed at.
test "decode_log needs a topics[0], which an anonymous event has not" {
  inspect(
    log_refused(
      name="Transfer",
      params=transfer_params(),
      topics=[],
      data="0x" + word("2a"),
    ),
    content=(
      #|InvalidData("`Transfer(address,address,uint256)`: the log carries no topics at all")
    ),
  )
}

///|
/// `event Named(string indexed what, uint256 n)` — the topic holds
/// `keccak256("hello")` and never held `"hello"`, so that is what comes back.
test "an indexed string comes back as the hash the topic holds" {
  let hash = @abi.event_topic("hello")
  let values = @abi.decode_log(
    name="Named",
    params=[{ ty: String, indexed: true }, { ty: Uint(256), indexed: false }],
    topics=[@abi.event_topic("Named(string,uint256)"), hash],
    data=@types.Hex::from_string("0x" + word("1")),
  )
  // the topic holds `keccak256("hello")`, and nothing can turn it back
  assert_eq(values[0], Bytes(hash.to_bytes()))
  assert_eq(values[1], Uint(1N))
}

///|
/// A value type indexed is the same word it would have been in `data`, sign
/// bit and all.
test "decode_log reads a topic as the type it was declared" {
  inspect(
    decoded_log(
      name="Flagged",
      params=[{ ty: Bool, indexed: true }, { ty: Int(8), indexed: true }],
      topics=[
        @abi.event_topic("Flagged(bool,int8)"),
        topic("1"),
        topic(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
      ],
      data="0x",
    ),
    content="[Bool(true), Int(-1)]",
  )
}

///|
test "a topic that is not a word is not a topic" {
  inspect(
    log_refused(
      name="Flagged",
      params=[{ ty: Bool, indexed: true }],
      // 31 bytes: a word short of a topic
      topics=[
        @abi.event_topic("Flagged(bool)"),
        @types.Hex::from_string("0x" + "00".repeat(31)) catch {
          e => abort("bad test topic: \{e}")
        },
      ],
      data="0x",
    ),
    content=(
      #|InvalidData("a topic is 32 bytes, and this one is 31")
    ),
  )
}

///|
/// An event with nothing indexed is one topic and a block of data — the case
/// where `decode_log` is `decode` with the topic checked.
test "an event with nothing indexed is its data and one topic" {
  inspect(
    decoded_log(
      name="Paused",
      params=[{ ty: Address, indexed: false }],
      topics=[@abi.event_topic("Paused(address)")],
      data="0x" + word("dead"),
    ),
    content=(
      #|[Address("0x000000000000000000000000000000000000dead")]
    ),
  )
}
