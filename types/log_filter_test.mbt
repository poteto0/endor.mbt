///|
/// The `Transfer(address,address,uint256)` topic, which every filter test below
/// is written around: it is the one topic a reader will recognise.
const TRANSFER : String = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

///|
const APPROVAL : String = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

///|
/// A 32-byte topic. Parsing one cannot fail here, so the tests spend no lines
/// on the codec they are not exercising.
fn topic(s : String) -> @types.Topic {
  @types.Topic::exactly(calldata(s)) catch {
    e => abort("bad test topic: \{e}")
  }
}

///|
fn block_hash(s : String) -> @types.BlockHash {
  @types.BlockHash::from_string(s) catch {
    e => abort("bad test block hash: \{e}")
  }
}

///|
/// A single alternative goes on the wire as the bare hex string, which is the
/// form a node answers a log's `topics` in too.
test "a topic with one alternative is the hex itself" {
  inspect(topic(TRANSFER).to_json().stringify(), content="\"\{TRANSFER}\"")
}

///|
/// The OR an `Array[Hex]` could not express: one filter following two events.
test "a topic with several alternatives is the array of them" {
  let t = @types.Topic::any_of([calldata(TRANSFER), calldata(APPROVAL)]) catch {
    e => fail("unexpected error \{e}")
  }
  inspect(t.to_json().stringify(), content="[\"\{TRANSFER}\",\"\{APPROVAL}\"]")
}

///|
/// A topic is a 32-byte word, always — an address or a selector at a topic
/// position is a filter that silently matches nothing, so it is refused where
/// it is written instead.
test "a topic that is not 32 bytes is refused" {
  try @types.Topic::any_of([calldata("0xdeadbeef")]) catch {
    @types.CodecError::InvalidLength(msg) =>
      assert_true(msg.has_prefix("a topic is 32 bytes"))
    e => fail("expected InvalidLength, but not \{e}")
  } noraise {
    _ => fail("expected a 4-byte topic to be rejected")
  }
}

///|
/// Not the same thing as "match anything": that position is `None` in the
/// filter's `topics`, and an empty set would read as the opposite of what it is.
test "a topic with no alternatives at all is refused" {
  try @types.Topic::any_of([]) catch {
    @types.CodecError::InvalidLength(msg) =>
      assert_true(msg.has_prefix("a topic needs at least one"))
    e => fail("expected InvalidLength, but not \{e}")
  } noraise {
    _ => fail("expected an empty alternative list to be rejected")
  }
}

///|
test "a range filter encodes every criterion it was given" {
  let filter = @types.LogFilter::range(
    from_block=Number(436),
    to_block=Latest,
    address=[address("0x52908400098527886E0F7030069857D2E4169EE7")],
    topics=[Some(topic(TRANSFER))],
  )
  inspect(
    filter.to_json().stringify(),
    content=(
      #|{"fromBlock":"0x1b4","toBlock":"latest","address":"0x52908400098527886e0f7030069857d2e4169ee7","topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"]}
    ),
  )
}

///|
/// A criterion nobody gave is left out rather than sent as `null`: an absent
/// bound is how the RPC spells "the latest block".
test "a filter that constrains nothing is the empty object" {
  inspect(@types.LogFilter::range().to_json().stringify(), content="{}")
}

///|
/// Several addresses are the array; one is the bare string. Both are accepted
/// by a node, and the single form is what every wallet has always been sent.
test "addresses are one or many" {
  let filter = @types.LogFilter::range(address=[
    address("0x52908400098527886E0F7030069857D2E4169EE7"),
    address("0x8617E340B3D01FA5F11F306F4090FD50E238070D"),
  ])
  inspect(
    filter.to_json().stringify(),
    content=(
      #|{"address":["0x52908400098527886e0f7030069857d2e4169ee7","0x8617e340b3d01fa5f11f306f4090fd50e238070d"]}
    ),
  )
}

///|
/// The three-state position the issue turns on: `null` holds topic 1 open so
/// that the constraint on topic 2 stays at index 2 rather than sliding down to
/// where it would match a sender.
test "an unconstrained topic position is null, and still occupies its index" {
  let filter = @types.LogFilter::range(topics=[
    Some(topic(TRANSFER)),
    None,
    Some(topic(APPROVAL)),
  ])
  inspect(
    filter.to_json().stringify(),
    content="{\"topics\":[\"\{TRANSFER}\",null,\"\{APPROVAL}\"]}",
  )
}

///|
/// `blockHash` and the range are exclusive in the RPC, and there is no
/// constructor that produces both — so this is the only shape the block form
/// has.
test "a block filter names the block and no range" {
  let hash = block_hash(
    "0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5",
  )
  let filter = @types.LogFilter::at_block(hash, topics=[Some(topic(TRANSFER))])
  inspect(
    filter.to_json().stringify(),
    content="{\"blockHash\":\"0xb6de5c3c1b70d24de3ea4eb90a6c9f1f5eb1d0e6a5e3b3f1b7e0c0b9a8d7c6e5\",\"topics\":[\"\{TRANSFER}\"]}",
  )
}
