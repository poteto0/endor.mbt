// The helpers in `json.mbt` are package-private, so every test of them so far
// has been a test of a *decoder* that happens to call one — `Log::from_json`
// proving `required_field` by rejecting a log with no `address`. That works
// until two decoders disagree about which of them a message names, which is
// what these tests pin down directly.

///|
/// A decoder whose failure is one no helper here raises on its own, so a test
/// can tell "the element's error came back" apart from "the helper reported a
/// shape problem of its own".
fn strings_only(j : Json) -> String raise CodecError {
  guard j is String(s) else { raise InvalidHex("not a string") }
  s
}

///|
/// A log-shaped object, in the sense that matters here: the helpers take a
/// decoded `Map`, not the JSON around it.
fn some_fields() -> Map[String, Json] {
  {
    "topics": Json::array(["0xaa".to_json(), "0xbb".to_json()]),
    "data": "0xcc".to_json(),
    "contractAddress": Json::null(),
  }
}

///|
/// Both readers answer with what is inside, and both name `what` when it is the
/// wrong shape — that name is the only thing telling a caller *which* level of a
/// nested answer went wrong, since a log inside a receipt fails through the same
/// two functions the receipt did.
test "a value of the wrong shape is reported against the name it was read for" {
  inspect(
    json_object(Json::object(some_fields()), what="log").length(),
    content="3",
  )
  inspect(
    json_array(Json::array(["0xaa".to_json()]), what="topics").length(),
    content="1",
  )
  try json_object(Json::array([]), what="receipt") |> ignore catch {
    InvalidJson(msg) => inspect(msg, content="expected receipt object")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected an array to be rejected as an object")
  }
  try json_array(Json::string("0x0"), what="logs") |> ignore catch {
    InvalidJson(msg) => inspect(msg, content="expected logs array")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a string to be rejected as an array")
  }
}

///|
test "every element of an array is decoded, in order" {
  let decoded = json_array_of(
    Json::array(["a".to_json(), "b".to_json()]),
    what="topics",
    strings_only,
  )
  inspect(decoded.length(), content="2")
  inspect(decoded[0], content="a")
  inspect(decoded[1], content="b")
  // an empty array decodes to an empty array — a node that matched nothing
  // answers this way, and it is not an absence to report
  inspect(
    json_array_of(Json::array([]), what="logs", strings_only).length(),
    content="0",
  )
}

///|
/// An element the decoder cannot read is *that decoder's* failure, not a shape
/// problem with the array. Re-wrapping it here would bury the reason: a caller
/// would learn that "logs" went wrong and never learn that one of them held a
/// value that is not hex.
test "an element's own error is what surfaces, unwrapped" {
  try
    json_array_of(Json::array([Json::number(1)]), what="topics", strings_only)
    |> ignore
  catch {
    InvalidHex(msg) => inspect(msg, content="not a string")
    e => fail("expected the element's InvalidHex, but not \{e}")
  } noraise {
    _ => fail("expected a number element to be rejected")
  }
}

///|
/// `array_field` reads through two names, and they are deliberately different:
/// a *missing* field is the enclosing shape's problem and names it ("log has no
/// topics"), while a field that is present and not an array is the field's own
/// and names that ("expected topics array"). Getting these the same way round
/// would leave one of the two messages unable to say where to look.
test "an array field names the object when absent and the field when misshapen" {
  let topics = array_field(some_fields(), "topics", what="log", strings_only)
  inspect(topics.length(), content="2")
  inspect(topics[0], content="0xaa")
  try
    array_field(some_fields(), "logs", what="log", strings_only) |> ignore
  catch {
    InvalidJson(msg) => inspect(msg, content="log has no logs")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a missing field to be rejected")
  }
  try
    array_field(some_fields(), "data", what="log", strings_only) |> ignore
  catch {
    InvalidJson(msg) => inspect(msg, content="expected data array")
    e => fail("expected InvalidJson, but not \{e}")
  } noraise {
    _ => fail("expected a non-array field to be rejected")
  }
}

///|
/// `null` and absent are the same fact. A node spells "not applicable" as
/// `null` — a receipt's `to` on a deployment, a pending block's `number` — and a
/// decoder that treated the two apart would have to check for both at every
/// field it reads.
test "a field carrying null is an absent field" {
  let fields = some_fields()
  assert_true(optional_field(fields, "data") is Some(String("0xcc")))
  assert_true(optional_field(fields, "contractAddress") is None)
  assert_true(optional_field(fields, "nothingHere") is None)
  // and `required_field` refuses both the same way
  for name in ["contractAddress", "nothingHere"] {
    try required_field(fields, name, what="receipt") |> ignore catch {
      InvalidJson(msg) => inspect(msg, content="receipt has no \{name}")
      e => fail("expected InvalidJson, but not \{e}")
    } noraise {
      _ => fail("expected \{name} to read as absent")
    }
  }
}

///|
/// The decoder an optional field is read through only ever sees a value, which
/// is the point: `Hex::from_json` and friends need no `null` case of their own.
test "an optional field is decoded only when it is there" {
  let fields = some_fields()
  assert_true(optional_map(fields, "data", strings_only) is Some("0xcc"))
  assert_true(optional_map(fields, "contractAddress", strings_only) is None)
  assert_true(optional_map(fields, "nothingHere", strings_only) is None)
}
