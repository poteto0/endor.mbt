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
