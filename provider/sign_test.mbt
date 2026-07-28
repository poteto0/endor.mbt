///|
async test "can sign a message" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="personal_sign",
      response=Json::string("0x" + "ab".repeat(65)),
    )
    let signature = @provider.sign_message(
      provider,
      test_address(),
      "hello 🔥",
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(signature.byte_length(), content="65")

    // EIP-191 order: the message — as the UTF-8 bytes in hex, which is why the
    // message signed here is not ASCII — comes first, and the account second.
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "personal_sign",
        #|    Array(
        #|      [
        #|        String("0x68656c6c6f20f09f94a5"),
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
/// Signing always prompts, so a decline is the expected failure and it reaches
/// the caller as 4001 rather than as a decode failure.
async test "error sign message rejected by user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="personal_sign",
      error=@provider.ProviderError::UserRejected,
    )
    try @provider.sign_message(provider, test_address(), "hello") catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// Asking for an account the dapp was never authorized for is 4100, and it is
/// told apart from a rejection.
async test "error sign message from an unauthorized account" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="personal_sign",
      error=@provider.ProviderError::Unauthorized,
    )
    try @provider.sign_message(provider, test_address(), "hello") catch {
      @provider.ProviderError::Unauthorized => ()
      e => fail("expected Unauthorized, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// An answer that is not a signature is the SDK's own problem, so it surfaces
/// as an internal error naming the method.
async test "error sign message answered with a non-signature" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="personal_sign",
      response=Json::string("not hex"),
    )
    try @provider.sign_message(provider, test_address(), "hello") catch {
      e =>
        inspect(
          e,
          content=(
            #|Rpc(code=-32603, message="decode personal_sign: InvalidHex(not hex)")
          ),
        )
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// The EIP-712 document a `Permit` is signed as, trimmed to the fields every
/// typed-data signature carries.
fn permit_typed_data() -> Json {
  {
    "types": { "EIP712Domain": Json::array([]), "Permit": Json::array([]) },
    "primaryType": "Permit",
    "domain": { "name": "Endor", "chainId": Json::number(1) },
    "message": { "value": Json::number(1) },
  }
}

///|
async test "can sign typed data" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on(
      method_name="eth_signTypedData_v4",
      response=Json::string("0x" + "cd".repeat(65)),
    )
    let signature = @provider.sign_typed_data(
      provider,
      test_address(),
      permit_typed_data(),
    ) catch {
      e => fail("unexpected error \{e}")
    }
    inspect(signature.byte_length(), content="65")

    // the account comes first, and the document reaches the wallet serialized
    // — v4 takes a string, not a nested object
    debug_inspect(
      provider.last_call(),
      content=(
        #|Some(
        #|  (
        #|    "eth_signTypedData_v4",
        #|    Array(
        #|      [
        #|        String("0x52908400098527886e0f7030069857d2e4169ee7"),
        #|        String("{\"types\":{\"EIP712Domain\":[],\"Permit\":[]},\"primaryType\":\"Permit\",\"domain\":{\"name\":\"Endor\",\"chainId\":1},\"message\":{\"value\":1}}"),
        #|      ],
        #|    ),
        #|  ),
        #|)
      ),
    )
  })
}

///|
async test "error sign typed data rejected by user" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_signTypedData_v4",
      error=@provider.ProviderError::UserRejected,
    )
    try
      @provider.sign_typed_data(provider, test_address(), permit_typed_data())
    catch {
      @provider.ProviderError::UserRejected => ()
      e => fail("expected UserRejected, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}

///|
/// A wallet that does not know `eth_signTypedData_v4` at all answers 4200, and
/// that too propagates untouched.
async test "error sign typed data unsupported by the wallet" {
  @async.with_task_group(_ => {
    let provider : @provider.MockProvider = @provider.MockProvider::new().on_error(
      method_name="eth_signTypedData_v4",
      error=@provider.ProviderError::UnsupportedMethod,
    )
    try
      @provider.sign_typed_data(provider, test_address(), permit_typed_data())
    catch {
      @provider.ProviderError::UnsupportedMethod => ()
      e => fail("expected UnsupportedMethod, but not \{e}")
    } noraise {
      _ => fail("expected fail, but success")
    }
  })
}
