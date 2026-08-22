///|
/// go-ethereum's `crypto_test.go` test key, whose address is pinned below.
const TEST_PRIV = "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032"

///|
/// Address normalizes to lowercase.
test "can normalize address" {
  inspect(
    @types.Address::from_string("0x52908400098527886E0F7030069857D2E4169EE7").to_string(),
    content="0x52908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
/// Invalid when not prefixed with `0x`.
test "invalid if missing 0x prefix" {
  try
    @types.Address::from_string("52908400098527886e0f7030069857d2e4169ee7")
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when non-hex characters exist.
test "invalid if contains non hex character" {
  try
    @types.Address::from_string("0x52908400098527886e0f7030069857d2e4169eeG")
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// Invalid when the address is not exactly 20 bytes.
test "invalid if wrong length" {
  try @types.Address::from_string("0x1234") catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  try
    @types.Address::from_string("0x52908400098527886e0f7030069857d2e4169ee700")
  catch {
    InvalidLength(_) => ()
    e => fail("expected invalid length, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "can convert to json" {
  let address = @types.Address::from_string(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  inspect(
    address.to_json().stringify(),
    content="\"0x52908400098527886e0f7030069857d2e4169ee7\"",
  )
}

///|
test "can create from json" {
  let address = @types.Address::from_json(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  inspect(
    address.to_string(),
    content="0x52908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
test "error if not string json" {
  try @types.Address::from_json(0) catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
test "debug address" {
  let address = @types.Address::from_string(
    "0x52908400098527886e0f7030069857d2e4169ee7",
  )
  inspect(
    address.to_string(),
    content="0x52908400098527886e0f7030069857d2e4169ee7",
  )
}

///|
/// The account-listing RPCs answer with an array of address strings.
test "can create many from json" {
  let addresses = @types.Address::array_from_json([
    "0x52908400098527886E0F7030069857D2E4169EE7", "0x52908400098527886E0F7030069857D2E4169EE8",
  ])
  inspect(addresses.length(), content="2")
  inspect(
    addresses[0].to_string(),
    content="0x52908400098527886e0f7030069857d2e4169ee7",
  )
  inspect(
    @types.Address::array_from_json(Json::array([])).length(),
    content="0",
  )
}

///|
test "error if not an array of addresses" {
  // not an array at all
  try @types.Address::array_from_json("0x1234") catch {
    InvalidJson(_) => ()
    e => fail("expected invalid json, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }

  // an array holding something that is not an address
  try
    @types.Address::array_from_json(Json::array(["invalid".to_json()]))
  catch {
    InvalidHex(_) => ()
    e => fail("expected invalid hex, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The test vectors listed in EIP-55 itself: the checksummed spelling must be
/// what the lowercase form renders back to.
test "eip-55 test vectors round-trip" {
  let vectors = [
    // all caps
    "0x52908400098527886E0F7030069857D2E4169EE7", "0x8617E340B3D01FA5F11F306F4090FD50E238070D",
    // all lower
     "0xde709f2102306220921060314715629080e2fb77", "0x27b1fdb04752bbc536007a920d24acb045561c26",
    // normal
     "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
    "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB", "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
  ]
  for v in vectors {
    // parsing the checksummed form is accepted, and either uniform casing —
    // which carries no checksum at all — produces exactly that spelling back
    assert_eq(@types.Address::from_string(v).to_checksum_string(), v)
    assert_eq(@types.Address::from_string(v.to_lower()).to_checksum_string(), v)
    let upper = "0x" + v[2:].to_owned().to_upper()
    assert_eq(@types.Address::from_string(upper).to_checksum_string(), v)
  }
}

///|
/// Casing carries no information on the wire: all forms store and serialize
/// lowercase, while `Show` is the display form.
test "wire form stays lowercase, display is checksummed" {
  let a = @types.Address::from_string(
    "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
  )
  inspect(a.to_string(), content="0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
  inspect(
    a.to_json().stringify(),
    content="\"0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed\"",
  )
  inspect(a, content="0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
}

///|
/// Mixed case claims a checksum, so a single flipped letter must be rejected.
test "invalid if mixed-case checksum does not match" {
  // `5aAeb…` with the leading `a` of the checksummed form uppercased
  try
    @types.Address::from_string("0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
  catch {
    InvalidChecksum(_) => ()
    e => fail("expected invalid checksum, but not \{e}")
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// go-ethereum's `crypto_test.go` test key and the address it derives — the
/// vector that proves the whole chain, from a private key through the curve
/// and Keccak-256 to the twenty bytes a node would see.
test "derives the known address from a private key" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let address = @types.Address::from_public_key(key.public_key())
  inspect(
    address.to_string(),
    content="0x970e8128ab834e8eac17ab8e3812f010678cf791",
  )
}

///|
/// A derived address is checksummed like any other, and is the same value the
/// parser produces from its own digits.
test "a derived address is an ordinary address" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let derived = @types.Address::from_public_key(key.public_key())
  assert_eq(
    derived,
    @types.Address::from_string("0x970e8128ab834e8eac17ab8e3812f010678cf791"),
  )
  inspect(
    derived.to_checksum_string(),
    content="0x970E8128AB834E8EAC17Ab8E3812F010678CF791",
  )
}

///|
/// Only the uncompressed SEC1 form carries both coordinates, so nothing else
/// names a point this can hash.
test "rejects anything that is not an uncompressed public key" {
  let key = @secp256k1.PrivateKey::from_bytes(@codec.bytes_of_digits(TEST_PRIV))
  let public_key = key.public_key()
  // The 64 coordinate bytes with the tag already stripped.
  let untagged = public_key[1:].to_owned()
  // The right length, the wrong tag: what a compressed key's prefix looks like.
  let mistagged = Bytes::makei(65, i => {
    if i == 0 {
      b'\x02'
    } else {
      public_key[i]
    }
  })
  for wrong in [untagged, mistagged, Bytes::new(0)] {
    try @types.Address::from_public_key(wrong) |> ignore catch {
      InvalidLength(_) => ()
      e => fail("expected invalid length, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  }
}

///|
/// go-ethereum's `TestSign`: its test key, the `keccak256("foo")` it signs and
/// the 65 bytes it produces are all geth's, and the address is pinned above
/// from geth too. Recovery has to close that loop without either side of it
/// being something this repository chose.
test "the geth signature recovers the geth address" {
  let signature = @secp256k1.Signature::from_bytes(
    @codec.bytes_of_digits(
      "d155e94305af7e07dd8c32873e5c03cb95c9e05960ef85be9c07f671da58c737" +
      "18c19adc397a211aa9e87e519e2038c5a3b658618db335f74f800b8e0cfeef44" +
      "01",
    ),
  )
  let digest = @keccak.keccak256(b"foo")
  let signer = @types.Address::recover(digest, signature)
  assert_eq(
    signer,
    @types.Address::from_string("0x970e8128ab834e8eac17ab8e3812f010678cf791"),
  )
}

///|
/// A signature that recovers nothing raises the curve's error and not the
/// codec's: the bytes this derives from never reach the address parser.
test "a signature that recovers nothing raises a curve error" {
  let signature = @secp256k1.Signature::from_bytes(
    @codec.bytes_of_digits(
      "0000000000000000000000000000000000000000000000000000000000000005" +
      "0000000000000000000000000000000000000000000000000000000000000001" +
      "00",
    ),
  )
  try
    @types.Address::recover(@keccak.keccak256(b"foo"), signature) |> ignore
  catch {
    e =>
      assert_eq(e, @secp256k1.InvalidSignature("r is no point's x coordinate"))
  } noraise {
    _ => fail("expected fail, but success")
  }
}

///|
/// The checksum spelling is a memo, so asking for it must not make one address
/// differ from another that has not been asked — nor change what `Debug` says.
test "showing an address does not change the value" {
  let shown = @types.Address::from_string(LOWER_ADDRESS)
  let untouched = @types.Address::from_string(LOWER_ADDRESS)
  assert_eq(shown.to_checksum_string(), MIXED_ADDRESS)
  // asked once, asked twice: the same answer, and still the same value
  assert_eq(shown.to_checksum_string(), MIXED_ADDRESS)
  assert_eq(shown, untouched)
  assert_eq(@debug.to_string(shown), @debug.to_string(untouched))
  inspect(shown, content=MIXED_ADDRESS)
}

///|
/// A checksummed address arrives with its spelling already proven, so showing
/// it back costs nothing and answers exactly what was passed in.
test "a checksummed address keeps the spelling it proved" {
  let a = @types.Address::from_string(MIXED_ADDRESS)
  inspect(a.to_string(), content=LOWER_ADDRESS)
  inspect(a.to_checksum_string(), content=MIXED_ADDRESS)
}
