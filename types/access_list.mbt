///|
/// One entry of an access list: an address a transaction says it will touch,
/// and the storage slots of that address it will touch.
///
/// Declaring them up front is what EIP-2930 buys — the first access to
/// something on the list is charged the warm price instead of the cold one —
/// and a wrong list costs gas but never changes what the transaction does.
pub struct AccessListItem {
  priv address : Address
  priv storage_keys : Array[Hex]
} derive(Eq, Debug)

///|
pub impl Show for AccessListItem with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The list a transaction carries. A slot on it is warm from the start; an
/// empty list is the ordinary transaction, and costs nothing extra.
pub type AccessList = Array[AccessListItem]

///|
/// Declare `address`, and the storage slots of it the transaction will read or
/// write. An address with no slots is the useful minimum: it warms the account
/// itself.
///
/// A storage key is a word — a slot number is not a number that may be written
/// short — and anything else raises. The keys are copied in.
///
/// ```mbt check
/// test "doc: access list item" {
///   let item = @types.AccessListItem::new(
///     @types.Address::from_string("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
///     storage_keys=[
///       @types.Hex::from_string(
///         "0x0000000000000000000000000000000000000000000000000000000000000007",
///       ),
///     ],
///   )
///   assert_eq(item.storage_keys().length(), 1)
/// }
/// ```
pub fn AccessListItem::new(
  address : Address,
  storage_keys? : Array[Hex] = [],
) -> AccessListItem raise CodecError {
  AccessListItem::checked(address, storage_keys.copy())
}

///|
/// The same, over an array nothing else holds — what a decoder has just built,
/// and what `new` makes by copying. Validating and taking ownership is one
/// pass either way.
fn AccessListItem::checked(
  address : Address,
  storage_keys : Array[Hex],
) -> AccessListItem raise CodecError {
  for key in storage_keys {
    guard key.byte_length() == @codec.WORD_BYTES else {
      raise InvalidLength(
        "a storage key must be \{@codec.WORD_BYTES} bytes: \{key}",
      )
    }
  }
  AccessListItem::{ address, storage_keys }
}

///|
/// The address the entry is about.
pub fn AccessListItem::address(self : AccessListItem) -> Address {
  self.address
}

///|
/// The slots the entry declares, in the order they were given: the list is part
/// of the signed bytes, so re-ordering it is a different transaction.
pub fn AccessListItem::storage_keys(self : AccessListItem) -> Array[Hex] {
  self.storage_keys.copy()
}

///|
/// Encode as the JSON object a node takes inside a transaction and answers
/// with from `eth_createAccessList`.
pub fn AccessListItem::to_json(self : AccessListItem) -> Json {
  Json::object({
    "address": self.address.to_json(),
    "storageKeys": Json::array(self.storage_keys.map(Hex::to_json)),
  })
}

///|
/// Decode one entry a node answered with.
pub fn AccessListItem::from_json(j : Json) -> AccessListItem raise CodecError {
  let fields = json_object(j, what="access list item")
  AccessListItem::checked(
    Address::from_json(
      required_field(fields, "address", what="access list item"),
    ),
    array_field(fields, "storageKeys", what="access list item", Hex::from_json),
  )
}

///|
/// The pair RLP carries: the address, then its slots.
fn AccessListItem::to_rlp(self : AccessListItem) -> @rlp.Item {
  List([
    address_item(self.address),
    List(self.storage_keys.map(key => @rlp.Item::Bytes(key.to_bytes()))),
  ])
}

///|
/// The whole list as the one RLP field a transaction carries. An empty list is
/// `0xc0`, which is what a transaction that declares nothing holds there.
fn access_list_field(access_list : AccessList) -> @rlp.Item {
  List(access_list.map(AccessListItem::to_rlp))
}

///|
/// What `eth_createAccessList` answers: the list the node worked out by
/// executing the transaction, and the gas that transaction would then use.
///
/// `error` is the node reporting that the transaction it executed failed. The
/// list it built up to that point still comes back, so a caller that does not
/// look at `error` would sign an access list for a transaction that reverts.
pub(all) struct AccessListEstimate {
  /// The slots the node saw the transaction touch.
  access_list : AccessList
  /// The gas the transaction uses with that list on it.
  gas_used : Quantity
  /// Why the executed transaction failed, when it did.
  error : String?
} derive(Eq, Debug)

///|
pub impl Show for AccessListEstimate with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Decode the JSON object `eth_createAccessList` answers with.
pub fn AccessListEstimate::from_json(
  j : Json,
) -> AccessListEstimate raise CodecError {
  let fields = json_object(j, what="access list estimate")
  AccessListEstimate::{
    access_list: array_field(
      fields,
      "accessList",
      what="access list estimate",
      AccessListItem::from_json,
    ),
    gas_used: Quantity::from_json(
      required_field(fields, "gasUsed", what="access list estimate"),
    ),
    error: optional_map(fields, "error", j => {
      guard j is String(s) else {
        raise InvalidJson("expected an error string")
      }
      s
    }),
  }
}
