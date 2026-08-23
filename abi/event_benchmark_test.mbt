///|
/// One `Transfer` log's topics: the signature hash, then the two indexed
/// addresses. Every log in a batch is alike — what grows is how many there
/// are, not the work any one of them costs.
fn transfer_topics() -> Array[@types.Hex] {
  [
    @abi.event_topic("Transfer(address,address,uint256)"),
    topic("dead"),
    topic("beef"),
  ]
}

///|
/// `count` logs, built outside the timed closure so only decoding is measured.
fn create_logs(count : Int) -> Array[Array[@types.Hex]] {
  Array::makei(count, _ => transfer_topics())
}

///|
/// A batch decoded, one log at a time — the way a receipt's logs are read.
///
/// A log that fails to decode aborts rather than being counted as a fast
/// iteration: every guard `decode_log` gives up at is upstream of the decoding
/// this measures, so a broken decoder would otherwise show up here as the
/// fastest one yet.
fn decode_logs(
  logs : Array[Array[@types.Hex]],
  params : Array[@abi.EventParam],
  data : @types.Hex,
) -> Unit {
  for topics in logs {
    ignore(@abi.decode_log(name="Transfer", params~, topics~, data~)) catch {
      e => abort("decode_log: \{e}")
    }
  }
}

///|
/// The same batch against a declaration worked out once, which is what reading
/// a receipt's logs or a range scan's should actually do.
fn decode_logs_as(
  event : @abi.Event,
  logs : Array[Array[@types.Hex]],
  data : @types.Hex,
) -> Unit {
  for topics in logs {
    ignore(event.decode_log(topics~, data~)) catch {
      e => abort("Event::decode_log: \{e}")
    }
  }
}

///|
/// Both spellings of the read side, on the same logs.
///
/// The pair is the point: `decode_log` works the signature out per log, `Event`
/// works it out once. The gap holds no `keccak256` — `event_topic` remembers
/// one — so what is left in it is the signature string and the topics/data split.
test "bench: decode_log" (b : @bench.T) {
  let params = transfer_params()
  let data = @types.Hex::from_string("0x" + word("2a")) catch { _ => return }
  let one_log = create_logs(1)
  let many_logs = create_logs(1000)
  let event = @abi.Event::new(name="Transfer", params~) catch { _ => return }
  b.bench(name="Transfer", fn() { decode_logs(one_log, params, data) })
  b.bench(name="Transfer x1000", fn() { decode_logs(many_logs, params, data) })
  b.bench(name="Event", fn() { decode_logs_as(event, one_log, data) })
  b.bench(name="Event x1000", fn() { decode_logs_as(event, many_logs, data) })
}
