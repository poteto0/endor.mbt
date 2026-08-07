///|
/// Read a JSON object, naming the value in the error so a caller decoding a
/// nested shape (a log inside a receipt) reports which level went wrong.
fn json_object(j : Json, what~ : String) -> Map[String, Json] raise CodecError {
  guard j is Object(fields) else {
    raise InvalidJson("expected \{what} object")
  }
  fields
}

///|
/// Read a JSON array the same way.
fn json_array(j : Json, what~ : String) -> Array[Json] raise CodecError {
  guard j is Array(items) else { raise InvalidJson("expected \{what} array") }
  items
}

///|
/// Every element of a JSON array, decoded. A list is the shape of most of what
/// a node answers with — the accounts it lists, the logs it matched — and of
/// several fields inside those answers, so the loop is written once here and
/// each decoder names only what its elements are.
fn[T] json_array_of(
  j : Json,
  what~ : String,
  decode : (Json) -> T raise CodecError,
) -> Array[T] raise CodecError {
  let out = []
  for item in json_array(j, what~) {
    out.push(decode(item))
  }
  out
}

///|
/// A required field holding an array, decoded element by element: a block's
/// `transactions`, a receipt's `logs`, a log's `topics`. The field's name is
/// what the array is called, so it names the error too.
fn[T] array_field(
  fields : Map[String, Json],
  name : String,
  what~ : String,
  decode : (Json) -> T raise CodecError,
) -> Array[T] raise CodecError {
  json_array_of(required_field(fields, name, what~), what=name, decode)
}

///|
/// A field the shape cannot do without. A field carrying `null` counts as
/// absent: that is how a node spells "not applicable" (a receipt's `to` on a
/// deployment), and a decoder asking for it wants the same answer either way.
fn required_field(
  fields : Map[String, Json],
  name : String,
  what~ : String,
) -> Json raise CodecError {
  guard optional_field(fields, name) is Some(v) else {
    raise InvalidJson("\{what} has no \{name}")
  }
  v
}

///|
/// A field that may legitimately be missing or `null`.
fn optional_field(fields : Map[String, Json], name : String) -> Json? {
  match fields.get(name) {
    None | Some(Null) => None
    Some(v) => Some(v)
  }
}

///|
/// An optional field, decoded through `decode` when it is there. Every
/// nullable field in a block or a receipt is this shape: `null` and absent both
/// mean the same thing, and the decoder only ever sees a value.
fn[T] optional_map(
  fields : Map[String, Json],
  name : String,
  decode : (Json) -> T raise CodecError,
) -> T? raise CodecError {
  match optional_field(fields, name) {
    Some(v) => Some(decode(v))
    None => None
  }
}

///|
/// A required hex-quantity field, decoded to the number it denotes. Block
/// numbers and indices are all this shape, so the log, receipt, block and
/// transaction decoders read them through here rather than spelling out the two
/// steps each time.
fn quantity_field(
  fields : Map[String, Json],
  name : String,
  what~ : String,
) -> UInt64 raise CodecError {
  Quantity::from_json(required_field(fields, name, what~)).to_uint64()
}

///|
/// The same, for a quantity a node may answer `null` for: a pending block's
/// `number`, and every field that is `null` until a transaction is mined.
fn optional_quantity_field(
  fields : Map[String, Json],
  name : String,
) -> UInt64? raise CodecError {
  optional_map(fields, name, j => Quantity::from_json(j).to_uint64())
}
