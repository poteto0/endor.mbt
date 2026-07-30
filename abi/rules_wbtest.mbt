///|
test "can judge valid uint value from abi word bigint" {
  // uint8: max value
  inspect(_is_valid_uint_bits_word(BigInt::from_int(255), 8), content="true")

  // uint8: overflow
  inspect(_is_valid_uint_bits_word(BigInt::from_int(256), 8), content="false")

  // uint256
  inspect(_is_valid_uint_bits_word(BigInt::from_int(256), 256), content="true")
}

///|
test "can judge valid int value from abi word bigint" {
  // int8: positive max
  inspect(_is_valid_int_bits_word(BigInt::from_int(127), 8), content="true")

  // int8: negative min
  inspect(
    _is_valid_int_bits_word(
      BigInt::from_string(
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80",
        radix=16,
      ),
      8,
    ),
    content="true",
  )

  // int8: positive overflow
  inspect(_is_valid_int_bits_word(BigInt::from_int(128), 8), content="false")

  // int8: negative value without sign extension
  inspect(_is_valid_int_bits_word(BigInt::from_int(255), 8), content="false")

  // int256
  inspect(
    _is_valid_int_bits_word(
      BigInt::from_string(
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        radix=16,
      ),
      256,
    ),
    content="true",
  )
}

///|
test "can judge valid address abi word" {
  inspect(
    _is_valid_address_word(
      "ffffffffffffffffffffffffdeadbeef00000000000000000000000000000001",
    ),
    content="false",
  )
  inspect(
    _is_valid_address_word(
      "000000000000000000000000deadbeef00000000000000000000000000000001",
    ),
    content="true",
  )
}

///|
test "can judge valid bytesN word" {
  inspect(
    _is_valid_bytes_word(
      "6162630000000000000000000000000000000000000000000000000000000000", 3,
    ),
    content="true",
  )
  inspect(
    _is_valid_bytes_word(
      "1111111111111111111111111111111111111111111111111111111111111111", 1,
    ),
    content="false",
  )
}
