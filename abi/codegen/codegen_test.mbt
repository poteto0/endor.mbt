///|
/// The ABI a standard ERC-20 compiles to — the same document as
/// `fixtures/abi/erc20.abi`, inlined so the test needs no file I/O and runs on
/// every backend.
let erc20_abi : String =
  #|[
  #|  {
  #|    "inputs": [
  #|      { "internalType": "uint256", "name": "_initialSupply", "type": "uint256" }
  #|    ],
  #|    "stateMutability": "nonpayable",
  #|    "type": "constructor"
  #|  },
  #|  {
  #|    "anonymous": false,
  #|    "inputs": [
  #|      {
  #|        "indexed": true,
  #|        "internalType": "address",
  #|        "name": "owner",
  #|        "type": "address"
  #|      },
  #|      {
  #|        "indexed": true,
  #|        "internalType": "address",
  #|        "name": "spender",
  #|        "type": "address"
  #|      },
  #|      {
  #|        "indexed": false,
  #|        "internalType": "uint256",
  #|        "name": "value",
  #|        "type": "uint256"
  #|      }
  #|    ],
  #|    "name": "Approval",
  #|    "type": "event"
  #|  },
  #|  {
  #|    "anonymous": false,
  #|    "inputs": [
  #|      {
  #|        "indexed": true,
  #|        "internalType": "address",
  #|        "name": "from",
  #|        "type": "address"
  #|      },
  #|      {
  #|        "indexed": true,
  #|        "internalType": "address",
  #|        "name": "to",
  #|        "type": "address"
  #|      },
  #|      {
  #|        "indexed": false,
  #|        "internalType": "uint256",
  #|        "name": "value",
  #|        "type": "uint256"
  #|      }
  #|    ],
  #|    "name": "Transfer",
  #|    "type": "event"
  #|  },
  #|  {
  #|    "inputs": [
  #|      { "internalType": "address", "name": "", "type": "address" },
  #|      { "internalType": "address", "name": "", "type": "address" }
  #|    ],
  #|    "name": "allowance",
  #|    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [
  #|      { "internalType": "address", "name": "spender", "type": "address" },
  #|      { "internalType": "uint256", "name": "amount", "type": "uint256" }
  #|    ],
  #|    "name": "approve",
  #|    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
  #|    "stateMutability": "nonpayable",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [{ "internalType": "address", "name": "", "type": "address" }],
  #|    "name": "balanceOf",
  #|    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [],
  #|    "name": "decimals",
  #|    "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [],
  #|    "name": "name",
  #|    "outputs": [{ "internalType": "string", "name": "", "type": "string" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [],
  #|    "name": "symbol",
  #|    "outputs": [{ "internalType": "string", "name": "", "type": "string" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [],
  #|    "name": "totalSupply",
  #|    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
  #|    "stateMutability": "view",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [
  #|      { "internalType": "address", "name": "to", "type": "address" },
  #|      { "internalType": "uint256", "name": "amount", "type": "uint256" }
  #|    ],
  #|    "name": "transfer",
  #|    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
  #|    "stateMutability": "nonpayable",
  #|    "type": "function"
  #|  },
  #|  {
  #|    "inputs": [
  #|      { "internalType": "address", "name": "from", "type": "address" },
  #|      { "internalType": "address", "name": "to", "type": "address" },
  #|      { "internalType": "uint256", "name": "amount", "type": "uint256" }
  #|    ],
  #|    "name": "transferFrom",
  #|    "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }],
  #|    "stateMutability": "nonpayable",
  #|    "type": "function"
  #|  }
  #|]

///|
test "generate: a getter with a single uint output" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|pub async fn[P : @provider.Provider] Erc20::total_supply(
        #|  self : Erc20,
        #|  provider : P,
        #|) -> BigInt raise @contract.ContractError {
        #|  @contract.uint_answer(
        #|    self.contract.call(provider, name="totalSupply", outputs=[Uint(256)]),
        #|    what="totalSupply",
        #|  )
        #|}
      ),
    ),
  )
  // the width the ABI declared survives: `decimals` is `uint8`, not `uint256`
  assert_true(out.code.contains("name=\"decimals\", outputs=[Uint(8)])"))
}

///|
test "generate: a getter with a single string output" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|pub async fn[P : @provider.Provider] Erc20::symbol(
        #|  self : Erc20,
        #|  provider : P,
        #|) -> String raise @contract.ContractError {
        #|  @contract.string_answer(
        #|    self.contract.call(provider, name="symbol", outputs=[String]),
        #|    what="symbol",
        #|  )
        #|}
      ),
    ),
  )
}

///|
test "generate: a state-changing function goes through send" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|pub async fn[P : @provider.Provider] Erc20::transfer(
        #|  self : Erc20,
        #|  provider : P,
        #|  from~ : @types.Address,
        #|  to~ : @types.Address,
        #|  amount~ : BigInt,
        #|) -> @types.TxHash raise @contract.ContractError {
        #|  self.contract.send(
        #|    provider,
        #|    from~,
        #|    name="transfer",
        #|    inputs=[Address, Uint(256)],
        #|    args=[Address(to), Uint(amount)],
        #|  )
        #|}
      ),
    ),
  )
  // `transfer` returns `bool`, but a broadcast transaction answers with a hash
  assert_false(out.code.contains("bool_answer"))
}

///|
test "generate: a parameter the ABI named `from` moves out of the way" {
  let out = @codegen.generate("Erc20", erc20_abi)
  // `from~` is the sender the template binds, so the ABI's own `from` is renamed
  assert_true(
    out.code.contains(
      (
        #|  from~ : @types.Address,
        #|  from_~ : @types.Address,
        #|  to~ : @types.Address,
      ),
    ),
  )
  assert_true(
    out.code.contains("args=[Address(from_), Address(to), Uint(amount)],"),
  )
}

///|
test "generate: an unnamed parameter is named by position" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|  arg0~ : @types.Address,
        #|  arg1~ : @types.Address,
      ),
    ),
  )
}

///|
test "generate: an event becomes its topic" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|pub fn Erc20::transfer_topic() -> @types.Hex {
        #|  @abi.event_topic("Transfer(address,address,uint256)")
        #|}
      ),
    ),
  )
}

///|
/// The decoder is the topic's other half: one matches a log, the other reads
/// it. The `indexed` flags out of the ABI are what put `from` and `to` in
/// `topics` and `value` in `data`, and they have to survive into the generated
/// `params`.
test "generate: an event becomes a decoder as well" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_true(
    out.code.contains(
      (
        #|pub fn Erc20::decode_transfer(
        #|  log : @types.Log,
        #|) -> (@types.Address, @types.Address, BigInt) raise @contract.ContractError {
        #|  let values = @abi.decode_log(
        #|    name="Transfer",
        #|    params=[
        #|      { ty: Address, indexed: true },
        #|      { ty: Address, indexed: true },
        #|      { ty: Uint(256), indexed: false },
        #|    ],
        #|    topics=log.topics,
        #|    data=log.data,
        #|  ) catch {
        #|    e => raise @contract.Abi(e)
        #|  }
      ),
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|  guard values is [Address(from), Address(to), Uint(value)] else {
      ),
    ),
  )
  assert_true(out.code.contains("  (from, to, value)\n"))
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// A single parameter is answered on its own: MoonBit has no one-element
/// tuple, and `(x)` is `x` rather than a tuple holding it.
test "generate: an event of one parameter answers with that parameter" {
  let out = @codegen.generate(
    "Vault",
    (
      #|[{ "type": "event", "name": "Paused", "inputs": [
      #|   { "name": "by", "type": "address", "indexed": true }] }]
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|) -> @types.Address raise @contract.ContractError {
      ),
    ),
  )
  assert_true(out.code.contains("  guard values is [Address(by)] else {"))
  assert_true(out.code.contains("  by\n}"))
}

///|
/// An event with nothing to decode keeps its topic and costs no comment: the
/// topic already says everything one of its logs carries.
test "generate: an event with no parameters gets no decoder" {
  let out = @codegen.generate(
    "Vault",
    (
      #|[{ "type": "event", "name": "Sealed", "inputs": [] }]
    ),
  )
  assert_true(out.code.contains("pub fn Vault::sealed_topic()"))
  assert_false(out.code.contains("decode_sealed"))
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// The event equivalent of a function's unsupported parameter — except that
/// the event keeps its topic, which is what a caller filters logs with before
/// decoding them by hand.
test "generate: an event whose arguments cannot be typed keeps its topic" {
  let out = @codegen.generate(
    "Vault",
    (
      #|[{ "type": "event", "name": "Blobbed", "inputs": [
      #|   { "name": "blob", "type": "bytes" }] },
      #| { "type": "event", "name": "Named", "inputs": [
      #|   { "name": "what", "type": "string", "indexed": true }] }]
    ),
  )
  assert_true(out.code.contains("pub fn Vault::blobbed_topic()"))
  assert_true(out.code.contains("pub fn Vault::named_topic()"))
  assert_false(out.code.contains("decode_blobbed"))
  assert_false(out.code.contains("decode_named"))
  assert_eq(
    out.skipped.join("\n"),
    (
      #|`Blobbed(bytes)`: parameter 0 is `bytes`, which is not generated
      #|event `Named(string)`: parameter 0 is an indexed `string`, which a log holds only as its hash
    ),
  )
}

///|
/// An anonymous event has no `topics[0]` at all, so neither half of what this
/// generator makes of an event means anything for one.
test "generate: an anonymous event is skipped entirely" {
  let out = @codegen.generate(
    "Vault",
    (
      #|[{ "type": "event", "name": "Quiet", "anonymous": true, "inputs": [
      #|   { "name": "who", "type": "address", "indexed": true }] }]
    ),
  )
  assert_false(out.code.contains("quiet_topic"))
  assert_false(out.code.contains("decode_quiet"))
  assert_eq(
    out.skipped.join("\n"),
    "event `Quiet(address)`: it is `anonymous`, so its logs carry no `topics[0]` to match or decode",
  )
}

///|
test "generate: nothing comes of a constructor" {
  let out = @codegen.generate("Erc20", erc20_abi)
  // it is dropped while reading, so it is not reported as a casualty either
  assert_eq(out.skipped.join("\n"), "")
  assert_false(out.code.contains("_initialSupply"))
}

///|
test "generate: the struct is named as asked" {
  let out = @codegen.generate("MyToken", erc20_abi)
  assert_true(out.code.contains("pub struct MyToken {"))
  assert_true(
    out.code.contains(
      "pub fn MyToken::new(address : @types.Address) -> MyToken",
    ),
  )
}

///|
/// A member this generator declines to translate is left out and named,
/// never approximated: a wrong signature that compiles is worse than an
/// absent one.
test "generate: unsupported members are skipped with a reason" {
  let abi =
    #|[
    #|  { "type": "function", "name": "holders", "stateMutability": "view",
    #|    "inputs": [],
    #|    "outputs": [{ "name": "", "type": "address[]" }] },
    #|  { "type": "function", "name": "quote", "stateMutability": "view",
    #|    "inputs": [],
    #|    "outputs": [{ "name": "a", "type": "uint256" },
    #|                { "name": "b", "type": "uint256" }] },
    #|  { "type": "function", "name": "commit", "stateMutability": "nonpayable",
    #|    "inputs": [{ "name": "blob", "type": "bytes" }],
    #|    "outputs": [] },
    #|  { "type": "function", "name": "settle", "stateMutability": "view",
    #|    "inputs": [{ "name": "order", "type": "tuple",
    #|                 "components": [{ "name": "who", "type": "address" }] }],
    #|    "outputs": [{ "name": "", "type": "bool" }] },
    #|  { "type": "function", "name": "paused", "stateMutability": "view",
    #|    "inputs": [],
    #|    "outputs": [{ "name": "", "type": "bool" }] }
    #|]
  let out = @codegen.generate("Odd", abi)
  inspect(
    out.skipped.join("\n"),
    content=(
      #|`holders()`: it returns `address[]`, which is not generated
      #|`quote()`: it returns 2 values, and only a single return value is generated
      #|`commit(bytes)`: parameter 0 is `bytes`, which is not generated
      #|`settle((address))`: parameter 0 is `(address)`, which is not generated
    ),
  )
  // what *was* supported still came out
  assert_true(
    out.code.contains("pub async fn[P : @provider.Provider] Odd::paused("),
  )
  assert_true(out.code.contains("@contract.bool_answer("))
  // and the file says so itself, for whoever reads it without the CLI output
  assert_true(
    out.code.contains(
      "//   - `holders()`: it returns `address[]`, which is not generated",
    ),
  )
}

///|
/// MoonBit has no overloading, so two Solidity functions of the same name
/// cannot both be generated. The second is reported rather than emitted.
test "generate: an overload is reported, not emitted twice" {
  let abi =
    #|[
    #|  { "type": "function", "name": "mint", "stateMutability": "nonpayable",
    #|    "inputs": [{ "name": "to", "type": "address" }], "outputs": [] },
    #|  { "type": "function", "name": "mint", "stateMutability": "nonpayable",
    #|    "inputs": [{ "name": "to", "type": "address" },
    #|               { "name": "amount", "type": "uint256" }], "outputs": [] }
    #|]
  let out = @codegen.generate("Nft", abi)
  inspect(
    out.skipped.join("\n"),
    content=(
      #|`mint(address,uint256)`: `mint` is already taken — MoonBit has no overloading
    ),
  )
}

///|
test "generate: a payable function takes the value it is sent" {
  let abi =
    #|[
    #|  { "type": "function", "name": "deposit", "stateMutability": "payable",
    #|    "inputs": [], "outputs": [] }
    #|]
  let out = @codegen.generate("Vault", abi)
  assert_true(
    out.code.contains(
      (
        #|  from~ : @types.Address,
        #|  value? : @types.Wei,
        #|) -> @types.TxHash raise @contract.ContractError {
      ),
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|  self.contract.send(provider, from~, name="deposit", value?)
      ),
    ),
  )
}

///|
test "generate: a document that is neither an ABI nor an artifact raises" {
  try @codegen.generate("Erc20", "{ }") catch {
    e =>
      inspect(
        e,
        content="InvalidJson(this JSON object is not an artifact: it holds neither `abi` nor `contracts`)",
      )
  } noraise {
    _ => fail("expected an object to have to be an artifact")
  }
  // a JSON value that is neither shape at all
  try @codegen.generate("Erc20", "42") catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected a bare number to raise")
  }
  try @codegen.generate("Erc20", "nope") catch {
    e => assert_true(e is InvalidJson(_))
  } noraise {
    _ => fail("expected unparseable JSON to raise")
  }
}

///|
test "generate: a type no contract can declare raises" {
  let abi =
    #|[
    #|  { "type": "function", "name": "odd", "stateMutability": "view",
    #|    "inputs": [], "outputs": [{ "name": "", "type": "uint7" }] }
    #|]
  try @codegen.generate("Odd", abi) catch {
    e => assert_true(e is InvalidAbi(_))
  } noraise {
    _ => fail("expected `uint7` to raise")
  }
}

///|
test "generate: the struct name has to be one MoonBit can spell" {
  try @codegen.generate("erc20", erc20_abi) catch {
    e => inspect(e, content="InvalidName(`erc20` is not a MoonBit type name)")
  } noraise {
    _ => fail("expected a lowercase name to raise")
  }
}

///|
test "naming" {
  inspect(@codegen.snake_case("balanceOf"), content="balance_of")
  inspect(@codegen.snake_case("transferFrom"), content="transfer_from")
  inspect(@codegen.snake_case("DOMAIN_SEPARATOR"), content="domain_separator")
  inspect(@codegen.snake_case("totalSupply"), content="total_supply")
  inspect(@codegen.snake_case("mintTo2Wallets"), content="mint_to2_wallets")
  inspect(@codegen.pascal_case("erc20"), content="Erc20")
  inspect(@codegen.pascal_case("my-token.abi"), content="MyTokenAbi")
  inspect(@codegen.pascal_case("MY_TOKEN"), content="MyToken")
}

///|
test "moon_pkg names every package the generated code spells" {
  let pkg = @codegen.moon_pkg()
  for
    dep in [
      "poteto0/endor/types", "poteto0/endor/abi", "poteto0/endor/contract", "poteto0/endor/provider",
    ] {
    assert_true(pkg.contains(dep))
  }
}

///|
/// The generator's type reader is exercised directly here rather than through
/// an ERC-20: a standard token uses four of the ~everything an ABI can
/// declare, and it is the *rest* that decides whether a member is generated or
/// skipped.
test "read: every width and alias the ABI spec allows" {
  let out = @codegen.generate(
    "Widths",
    (
      #|[
      #|  { "type": "function", "name": "small", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "uint8" }] },
      #|  { "type": "function", "name": "bare", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "uint" }] },
      #|  { "type": "function", "name": "signed", "stateMutability": "view",
      #|    "inputs": [{ "name": "d", "type": "int128" }],
      #|    "outputs": [{ "name": "", "type": "int" }] },
      #|  { "type": "function", "name": "owner", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "address" }] }
      #|]
    ),
  )
  assert_eq(out.skipped.join("\n"), "")
  // `uint` and `int` with no width are `uint256` / `int256`
  assert_true(out.code.contains("name=\"bare\", outputs=[Uint(256)])"))
  assert_true(out.code.contains("name=\"small\", outputs=[Uint(8)])"))
  // a signed value is its own `AbiValue` variant, constructor and helper
  assert_true(
    out.code.contains(
      (
        #|      inputs=[Int(128)],
        #|      args=[Int(d)],
        #|      outputs=[Int(256)],
      ),
    ),
  )
  assert_true(out.code.contains("@contract.int_answer("))
  assert_true(out.code.contains("@contract.address_answer("))
}

///|
/// A type the ABI spec does not define is not a type this generator may guess
/// at: `uint7` is not `uint8` rounded up, and a selector hashed from it would
/// address a function no contract has. So the whole document is refused rather
/// than the member skipped — a file this malformed is a build-system problem,
/// not a coverage gap.
test "read: a type no contract can declare stops the whole file" {
  let cases = [
    ("uint7", "a bit width that is not a multiple of 8"),
    ("bytes33", "more bytes than a word holds"),
    ("uint256x", "an unsigned width that is not a number"),
    ("int9z", "a signed width that is not a number"),
    ("bytes2z", "a byte count that is not a number"),
    ("wat", "a name the spec never defined"),
    ("]", "a closing bracket with nothing opening it"),
    ("uint256[x]", "an array length that is not a number"),
  ]
  for c in cases {
    let abi =
      #|[{ "type": "function", "name": "odd", "stateMutability": "view",
      #|   "inputs": [{ "name": "", "type": "TYPE" }], "outputs": [] }]
    try @codegen.generate("Odd", abi.replace(old="TYPE", new=c.0)) catch {
      e => assert_true(e is InvalidAbi(_))
    } noraise {
      _ => fail("expected `\{c.0}` (\{c.1}) to be refused")
    }
  }
}

///|
test "read: a parameter need not be named at all" {
  // some solc versions omit `name`, others write `""`: the same thing
  let out = @codegen.generate(
    "Anon",
    (
      #|[{ "type": "function", "name": "total", "stateMutability": "view",
      #|   "inputs": [{ "type": "address" }],
      #|   "outputs": [{ "type": "uint256" }] }]
    ),
  )
  assert_true(out.code.contains("arg0~ : @types.Address,"))
  assert_eq(out.skipped.join("\n"), "")
}

///|
test "read: a tuple is resolved through its components" {
  // refused as a *parameter* further on, but read first: an event of the same
  // shape needs the components flattened into its signature
  let out = @codegen.generate(
    "Book",
    (
      #|[
      #|  { "type": "event", "name": "Filled", "inputs": [
      #|      { "name": "order", "type": "tuple", "components": [
      #|          { "name": "who", "type": "address" },
      #|          { "name": "amount", "type": "uint256" }] },
      #|      { "name": "at", "type": "uint64" }] }
      #|]
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|  @abi.event_topic("Filled((address,uint256),uint64)")
      ),
    ),
  )
}

///|
test "read: a tuple with nothing to resolve is refused" {
  for
    abi in [
      (
        #|[{ "type": "event", "name": "E", "inputs": [
        #|   { "name": "o", "type": "tuple" }] }]
      ),
      (
        #|[{ "type": "event", "name": "E", "inputs": [
        #|   { "name": "o", "type": "tuple", "components": ["who"] }] }]
      ),
    ] {
    try @codegen.generate("Book", abi) catch {
      e => assert_true(e is InvalidAbi(_))
    } noraise {
      _ => fail("expected a tuple with no usable components to be refused")
    }
  }
}

///|
/// What a compiler emits is well-formed; what a hand-edited or truncated file
/// holds is not, and the difference has to surface as an error naming the
/// member rather than as generated code that silently lost a function.
test "read: a member that is not a well-formed ABI member is named" {
  let cases = [
    (
      (
        #|[42]
      ),
      "a member that is not an object",
    ),
    (
      (
        #|[{ "type": 7 }]
      ),
      "a `type` that is not a string",
    ),
    (
      (
        #|[{ "type": "function", "stateMutability": "view", "inputs": [] }]
      ),
      "a function with no name",
    ),
    (
      (
        #|[{ "type": "event", "inputs": [] }]
      ),
      "an event with no name",
    ),
    (
      (
        #|[{ "type": "function", "name": "f", "stateMutability": 1, "inputs": [] }]
      ),
      "a non-string `stateMutability`",
    ),
    (
      (
        #|[{ "type": "function", "name": "f", "stateMutability": "view", "inputs": {} }]
      ),
      "`inputs` that is not an array",
    ),
    (
      (
        #|[{ "type": "function", "name": "f", "stateMutability": "view", "inputs": [1] }]
      ),
      "an `inputs` entry that is not an object",
    ),
    (
      (
        #|[{ "type": "function", "name": "f", "stateMutability": "view",
        #|   "inputs": [{ "name": 1, "type": "address" }] }]
      ),
      "a parameter name that is not a string",
    ),
    (
      (
        #|[{ "type": "function", "name": "f", "stateMutability": "view",
        #|   "inputs": [{ "name": "a" }] }]
      ),
      "a parameter with no `type`",
    ),
    (
      (
        #|[{ "type": "event", "name": "E", "inputs": [{ "type": "wat" }] }]
      ),
      "an unnamed parameter of a type that does not exist",
    ),
  ]
  for c in cases {
    try @codegen.generate("Broken", c.0) catch {
      e => assert_true(e is InvalidAbi(_))
    } noraise {
      _ => fail("expected \{c.1} to be refused")
    }
  }
}

///|
/// Solidity before 0.6 wrote `constant: true` where later versions write
/// `stateMutability: "view"`. A tool that reads only the new spelling would
/// turn every getter in an old ABI into a transaction — which prompts the user
/// and costs gas to read a number.
test "read: a pre-0.6 ABI still says which functions only read" {
  let out = @codegen.generate(
    "Legacy",
    (
      #|[
      #|  { "name": "total", "constant": true, "inputs": [],
      #|    "outputs": [{ "name": "", "type": "uint256" }] },
      #|  { "name": "burn", "constant": false,
      #|    "inputs": [{ "name": "amount", "type": "uint256" }],
      #|    "outputs": [] }
      #|]
    ),
  )
  // `type` defaults to `function`, and `constant` decides read versus write
  assert_true(out.code.contains("@contract.uint_answer("))
  assert_true(
    out.code.contains(
      (
        #|  self.contract.send(
        #|    provider,
        #|    from~,
        #|    name="burn",
      ),
    ),
  )
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// A name MoonBit cannot spell is not worked around by inventing one: the
/// generated method would no longer be traceable to the ABI it came from, and
/// the caller is better told which member they have to reach by hand.
///
/// Only a function can reach this. An event's method is its name plus
/// `_topic`, and no keyword survives having a suffix stuck on it.
test "generate: a member MoonBit has no name for is skipped" {
  let out = @codegen.generate(
    "Odd",
    (
      #|[
      #|  { "type": "function", "name": "match", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "bool" }] },
      #|  { "type": "event", "name": "guard", "inputs": [] }
      #|]
    ),
  )
  inspect(
    out.skipped.join("\n"),
    content="`match()`: its name is not spellable as a MoonBit method",
  )
  assert_true(out.code.contains("pub fn Odd::guard_topic()"))
}

///|
/// The name is the one thing out of an ABI that reaches the generated file
/// unchanged, so it is the one thing that can write the file. `snake_case`
/// turns every character it does not know into `_`, which means a name built
/// out of quotes and newlines passes an identifier check on its *transformed*
/// spelling while its original bytes go into `name="…"` verbatim — closing the
/// string literal and continuing as MoonBit code the caller then compiles.
///
/// An ABI is a document that arrives from elsewhere: pasted out of a block
/// explorer, pulled from a registry, vendored by a dependency. So this is
/// refused at the point the name is read, and refused for the whole document:
/// a member named like this was not emitted by a compiler, and nothing else in
/// the file is more trustworthy than it is.
test "read: a name that could write the generated file is refused" {
  let cases = [
    (
      (
        #|[{ "type": "function", "name": "foo\") |> ignore\n  @provider.evil(",
        #|   "stateMutability": "view", "inputs": [],
        #|   "outputs": [{ "name": "", "type": "uint256" }] }]
      ),
      "a function name that closes the string literal",
    ),
    (
      (
        #|[{ "type": "event", "name": "E\n/// injected", "inputs": [] }]
      ),
      "an event name that breaks out of the doc comment",
    ),
    (
      (
        #|[{ "type": "function", "name": "42", "stateMutability": "view",
        #|   "inputs": [], "outputs": [{ "name": "", "type": "bool" }] }]
      ),
      "a name no Solidity compiler could have emitted",
    ),
  ]
  for c in cases {
    try @codegen.generate("Hostile", c.0) catch {
      e => assert_true(e is InvalidAbi(_))
    } noraise {
      _ => fail("expected \{c.1} to be refused")
    }
  }
}

///|
/// `$` is a Solidity identifier character and an inert one in MoonBit source,
/// so a name using it is generated rather than refused — the guard above is
/// about what can write the file, not about tidiness.
test "read: a `$` in a name is a name, not an injection" {
  let out = @codegen.generate(
    "Dollar",
    (
      #|[{ "type": "function", "name": "$peek", "stateMutability": "view",
      #|   "inputs": [], "outputs": [{ "name": "", "type": "bool" }] }]
    ),
  )
  assert_eq(out.members, ["$peek()"])
  assert_true(out.code.contains("name=\"$peek\""))
}

///|
test "generate: two events of one name cannot both be generated" {
  let out = @codegen.generate(
    "Dup",
    (
      #|[
      #|  { "type": "event", "name": "Moved",
      #|    "inputs": [{ "name": "a", "type": "address" }] },
      #|  { "type": "event", "name": "Moved",
      #|    "inputs": [{ "name": "a", "type": "uint256" }] }
      #|]
    ),
  )
  inspect(
    out.skipped.join("\n"),
    content="event `Moved(uint256)`: `moved_topic` is already taken",
  )
}

///|
/// `new` and `address` are the template's own methods. A contract with a
/// function called either would generate a file that does not compile, so the
/// clash is treated exactly like an overload.
test "generate: a function cannot take a name the template already uses" {
  let out = @codegen.generate(
    "Clash",
    (
      #|[
      #|  { "type": "function", "name": "address", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "address" }] },
      #|  { "type": "function", "name": "new", "stateMutability": "nonpayable",
      #|    "inputs": [], "outputs": [] }
      #|]
    ),
  )
  inspect(
    out.skipped.join("\n"),
    content=(
      #|`address()`: `address` is already taken — MoonBit has no overloading
      #|`new()`: `new` is already taken — MoonBit has no overloading
    ),
  )
}

///|
/// A getter returning nothing is not a getter. Rather than emit a method whose
/// answer is `Unit` — which would compile, run, and tell the caller nothing —
/// it is reported with the same reason as a multi-value return.
test "generate: a reading function with no return value is skipped" {
  let out = @codegen.generate(
    "Odd",
    (
      #|[{ "type": "function", "name": "check", "stateMutability": "pure",
      #|   "inputs": [], "outputs": [] }]
    ),
  )
  inspect(
    out.skipped.join("\n"),
    content="`check()`: it returns 0 values, and only a single return value is generated",
  )
}

///|
/// `pure` reads just as `view` does — it does not even touch state — so it
/// must not be mistaken for a function that needs signing.
test "generate: `pure` is a read, not a write" {
  let out = @codegen.generate(
    "Math",
    (
      #|[{ "type": "function", "name": "double", "stateMutability": "pure",
      #|   "inputs": [{ "name": "x", "type": "uint256" }],
      #|   "outputs": [{ "name": "", "type": "uint256" }] }]
    ),
  )
  assert_true(out.code.contains("self.contract.call("))
  assert_false(out.code.contains("self.contract.send("))
}

///|
/// A long signature is wrapped the way `moon fmt` wraps it, so a repository
/// that formats on commit does not show every generated file as a diff the
/// first time someone runs `just fmt`.
test "generate: a call too long for one line is wrapped like moon fmt" {
  let out = @codegen.generate(
    "Wide",
    (
      #|[{ "type": "function", "name": "settleTheWholeOutstandingPosition",
      #|   "stateMutability": "nonpayable",
      #|   "inputs": [{ "name": "counterparty", "type": "address" },
      #|              { "name": "amount", "type": "uint256" }],
      #|   "outputs": [] }]
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|  self.contract.send(
        #|    provider,
        #|    from~,
        #|    name="settleTheWholeOutstandingPosition",
        #|    inputs=[Address, Uint(256)],
        #|    args=[Address(counterparty), Uint(amount)],
        #|  )
      ),
    ),
  )
  // only the wrapping is `moon fmt`'s: a long method name is the ABI's doing
  for line in out.code.split("\n") {
    assert_true(line.length() <= 80 || line.contains("settle_the_whole"))
  }
}

///|
test "generate: a name that is not a type name is refused" {
  for name in ["", "_Erc20", "erc20", "Erc 20", "20Erc", "Erc-20", "type"] {
    try @codegen.generate(name, erc20_abi) catch {
      e => assert_true(e is InvalidName(_))
    } noraise {
      _ => fail("expected `\{name}` to be refused as a struct name")
    }
  }
}

///|
test "the error says which of the three mistakes it is" {
  inspect(
    @codegen.CodegenError::InvalidJson("x").to_string(),
    content="InvalidJson(x)",
  )
  inspect(
    @codegen.CodegenError::InvalidAbi("x").to_string(),
    content="InvalidAbi(x)",
  )
  inspect(
    @codegen.CodegenError::InvalidName("x").to_string(),
    content="InvalidName(x)",
  )
}

///|
/// `members` is what the generated file dispatches to. It is the half of the
/// answer `skipped` does not give — and the only one that can be hashed into
/// the selectors the file will actually put on the wire, which is what an
/// end-to-end check against a real chain compares.
test "generate: the members it covers are reported as canonical signatures" {
  let out = @codegen.generate("Erc20", erc20_abi)
  inspect(
    out.members.join("\n"),
    content=(
      #|allowance(address,address)
      #|approve(address,uint256)
      #|balanceOf(address)
      #|decimals()
      #|name()
      #|symbol()
      #|totalSupply()
      #|transfer(address,uint256)
      #|transferFrom(address,address,uint256)
      #|Approval(address,address,uint256)
      #|Transfer(address,address,uint256)
    ),
  )
  // in the document and in neither list: a preset over a deployed contract has
  // nothing to do with a constructor
  assert_eq(out.skipped.join("\n"), "")
}

///|
test "generate: a skipped member is in neither the code nor the members" {
  let out = @codegen.generate(
    "Odd",
    (
      #|[
      #|  { "type": "function", "name": "holders", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "address[]" }] },
      #|  { "type": "function", "name": "paused", "stateMutability": "view",
      #|    "inputs": [], "outputs": [{ "name": "", "type": "bool" }] }
      #|]
    ),
  )
  assert_eq(out.members, ["paused()"])
  assert_eq(out.skipped.length(), 1)
}

///|
/// The `AbiType` literals the generator emits are written out by hand in
/// `scalar`, not taken from `AbiType`'s derived `Debug`. That is deliberate —
/// emitted source must not depend on a debug format nothing pins — but it
/// leaves a promise the table makes silently: that what it spells is what the
/// type actually is.
///
/// So the promise is asserted here. If the table and the type ever disagree,
/// the generated file names an `AbiType` that does not exist and fails to
/// compile; this fails first, and says which spelling drifted.
test "generate: the type a call declares is the type the ABI said" {
  let out = @codegen.generate(
    "Widths",
    (
      #|[
      #|  { "type": "function", "name": "f", "stateMutability": "nonpayable",
      #|    "inputs": [
      #|      { "name": "a", "type": "address" }, { "name": "b", "type": "bool" },
      #|      { "name": "c", "type": "string" }, { "name": "d", "type": "uint8" },
      #|      { "name": "e", "type": "int128" }
      #|    ], "outputs": [] }
      #|]
    ),
  )
  let declared = [@abi.AbiType::Address, Bool, String, Uint(8), Int(128)]
    .map(ty => "\{ty}")
    .join(", ")
  assert_eq(declared, "Address, Bool, String, Uint(8), Int(128)")
  assert_true(out.code.contains("inputs=[\{declared}]"))
}

///|
/// A compiler artifact — the ABI *and* the creation code compiled from the same
/// source — as Foundry writes one.
///
/// The bytecode is real, and small enough to read: it is the creation code
/// `backend/anvil` deploys as its answer contract. `e2e/codegen_test.mbt`
/// deploys these same bytes to a real EVM, which is the half no comparison of
/// source text can make.
let counter_artifact : String =
  #|{
  #|  "abi": [
  #|    {
  #|      "type": "constructor",
  #|      "stateMutability": "nonpayable",
  #|      "inputs": [{ "name": "_start", "type": "uint256" }]
  #|    },
  #|    {
  #|      "type": "function",
  #|      "name": "count",
  #|      "stateMutability": "view",
  #|      "inputs": [],
  #|      "outputs": [{ "name": "", "type": "uint256" }]
  #|    }
  #|  ],
  #|  "bytecode": {
  #|    "object": "0x600a600c600039600a6000f3602a60005260206000f3"
  #|  }
  #|}

///|
/// The creation code an artifact carries is embedded as the bytes themselves,
/// so the generated `creation_code()` calls the total `Hex::from_bytes` and can
/// neither `abort` nor `raise` (#113).
test "generate: an artifact's creation code is embedded" {
  let out = @codegen.generate("Counter", counter_artifact)
  assert_true(out.deploys)
  assert_true(
    out.code.contains(
      (
        #|pub fn Counter::creation_code() -> @types.Hex {
        #|  @types.Hex::from_bytes(
        #|    b"\x60\x0a\x60\x0c\x60\x00\x39\x60\x0a\x60\x00\xf3\x60\x2a\x60\x00\x52\x60\x20\x60\x00\xf3",
        #|  )
        #|}
      ),
    ),
  )
  // the ABI's own members are generated exactly as they are without it
  assert_eq(out.members, ["count()"])
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// The constructor's arguments are what `deploy` takes, encoded behind the
/// creation code with no selector in front of them.
test "generate: an artifact deploys through @contract.deploy" {
  let out = @codegen.generate("Counter", counter_artifact)
  assert_true(
    out.code.contains(
      (
        #|pub async fn[P : @provider.Provider] Counter::deploy(
        #|  provider : P,
        #|  from~ : @types.Address,
        #|  start~ : BigInt,
        #|) -> Counter raise @contract.ContractError {
        #|  let deployed = @contract.deploy(
        #|    provider,
        #|    from~,
        #|    bytecode=Counter::creation_code(),
        #|    inputs=[Uint(256)],
        #|    args=[Uint(start)],
        #|  )
        #|  Counter::{ contract: deployed }
        #|}
      ),
    ),
  )
  // `deploy` makes the contract, so there is no `self` to make it on
  assert_false(out.code.contains("Counter::deploy(\n  self"))
}

///|
/// A bare ABI array carries no code, so nothing is deployed from it — and
/// nothing is reported as missing either, since the document never claimed to
/// hold any.
test "generate: an ABI document deploys nothing and says nothing" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_false(out.deploys)
  assert_false(out.code.contains("creation_code"))
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// `deploy` and `creation_code` are the template's, whether or not this document
/// filled them in: the same ABI passed again as an artifact must generate the
/// same members, so a contract with a `deploy()` of its own is skipped either
/// way.
test "generate: a function cannot take the name deploy, code or no code" {
  let abi =
    #|[
    #|  { "type": "function", "name": "deploy", "stateMutability": "nonpayable",
    #|    "inputs": [], "outputs": [] },
    #|  { "type": "function", "name": "creationCode", "stateMutability": "view",
    #|    "inputs": [], "outputs": [{ "name": "", "type": "uint256" }] }
    #|]
  let out = @codegen.generate("Odd", abi)
  assert_false(out.deploys)
  assert_eq(out.members, [])
  assert_eq(out.skipped.length(), 2)
  assert_true(out.skipped[0].contains("`deploy` is already taken"))
  assert_true(out.skipped[1].contains("`creation_code` is already taken"))
}

///|
/// A constructor's parameter is renamed exactly as a method's is: `from` is the
/// account that signs the deployment, so a constructor that named an argument
/// `from` gets it back one underscore longer.
test "generate: a constructor parameter moves out of the sender's way" {
  let out = @codegen.generate(
    "Vault",
    (
      #|{
      #|  "abi": [{ "type": "constructor", "stateMutability": "payable",
      #|            "inputs": [{ "name": "from", "type": "address" }] }],
      #|  "bytecode": "0x60006000"
      #|}
    ),
  )
  assert_true(
    out.code.contains(
      (
        #|  from~ : @types.Address,
        #|  from_~ : @types.Address,
        #|  value? : @types.Wei,
      ),
    ),
  )
  // a `payable` constructor is handed the ether it was sent
  assert_true(out.code.contains("args=[Address(from_)],\n    value?,\n"))
}

///|
/// An artifact with no `constructor` entry still deploys: a contract that
/// declares none has one taking nothing.
test "generate: a contract that declares no constructor still deploys" {
  let out = @codegen.generate(
    "Bare",
    (
      #|{ "abi": [], "bytecode": "0x60006000" }
    ),
  )
  assert_true(out.deploys)
  assert_true(
    out.code.contains(
      (
        #|pub async fn[P : @provider.Provider] Bare::deploy(
        #|  provider : P,
        #|  from~ : @types.Address,
        #|) -> Bare raise @contract.ContractError {
        #|  let deployed = @contract.deploy(
        #|    provider,
        #|    from~,
        #|    bytecode=Bare::creation_code(),
        #|  )
        #|  Bare::{ contract: deployed }
        #|}
      ),
    ),
  )
}

///|
/// Every shape a compiler writes the same two facts in is read as the same
/// document.
test "read: the artifact shapes every compiler emits" {
  let shapes = [
    // Hardhat: the bytecode is the string itself
    (
      "hardhat",
      (
        #|{ "abi": [], "bytecode": "0x6001" }
      ),
    ),
    // solc's standard JSON, per contract
    (
      "standard json",
      (
        #|{ "abi": [], "evm": { "bytecode": { "object": "6001" } } }
      ),
    ),
    // `solc --combined-json abi,bin`: `abi` is a JSON *string*, keyed by
    // `File.sol:Name`
    (
      "combined json",
      (
        #|{ "contracts": { "Foo.sol:Foo": { "abi": "[]", "bin": "6001" } } }
      ),
    ),
    // solc's standard JSON output, wrapped by file and then by name
    (
      "standard json output",
      (
        #|{ "contracts": { "Foo.sol": { "Foo": {
        #|  "abi": [], "evm": { "bytecode": { "object": "6001" } } } } } }
      ),
    ),
  ]
  for shape in shapes {
    let out = @codegen.generate("Foo", shape.1)
    assert_true(out.deploys)
    // the `0x` a compiler leaves off is read all the same
    assert_true(out.code.contains("from_bytes(b\"\\x60\\x01\")"), msg=shape.0)
  }
}

///|
/// An artifact holding several contracts is refused rather than resolved: one
/// document generates one struct, under the name the caller gave, and choosing
/// which contract wears it is not this generator's choice to make.
test "read: an artifact of several contracts says which they are" {
  let combined =
    #|{ "contracts": {
    #|  "Token.sol:Token": { "abi": [], "bin": "6001" },
    #|  "Vault.sol:Vault": { "abi": [], "bin": "6002" }
    #|} }
  try @codegen.generate("Token", combined) catch {
    e =>
      inspect(
        e,
        content="InvalidJson(this artifact holds 2 contracts (Token.sol:Token, Vault.sol:Vault); " +
          "generating one struct from it would mean choosing one — compile them apart, or pass one contract's artifact)",
      )
  } noraise {
    _ => fail("expected several contracts to be refused")
  }
}

///|
/// Bytecode that cannot be deployed is `skipped`, not raised: the file is not
/// broken — the ABI's twenty methods are still worth generating — it is this
/// one thing that cannot be done with it.
test "read: bytecode that cannot be deployed is skipped with a reason" {
  let cases = [
    // a library the linker never filled in
    (
      (
        #|{ "abi": [], "bytecode": "0x6001__$3f2a1c$__6002" }
      ),
      "unlinked library references",
    ),
    // what an interface or an abstract contract compiles to
    (
      (
        #|{ "abi": [], "bytecode": "0x" }
      ),
      "its bytecode is empty",
    ),
    (
      (
        #|{ "abi": [], "bin": "" }
      ),
      "its bytecode is empty",
    ),
    // half a byte
    (
      (
        #|{ "abi": [], "bytecode": "0x601" }
      ),
      "odd number of hex digits",
    ),
    (
      (
        #|{ "abi": [], "bytecode": "0xnothex" }
      ),
      "is not hex",
    ),
  ]
  for case in cases {
    let out = @codegen.generate("Foo", case.0)
    assert_false(out.deploys)
    assert_false(out.code.contains("creation_code"))
    assert_eq(out.skipped.length(), 1)
    assert_true(out.skipped[0].contains(case.1), msg=case.0)
    // and it is in the file the caller reads, not only in the CLI's output
    assert_true(out.code.contains("//   - `deploy`:"))
  }
}

///|
/// An artifact that simply holds no bytecode — `--combined-json abi` on its own
/// — is an ABI document that came in an object. Nothing is deployed and nothing
/// is reported: it never said it could be.
test "read: an artifact with no bytecode is an ABI document" {
  let out = @codegen.generate(
    "Foo",
    (
      #|{ "abi": [{ "type": "function", "name": "paused",
      #|            "stateMutability": "view", "inputs": [],
      #|            "outputs": [{ "name": "", "type": "bool" }] }] }
    ),
  )
  assert_false(out.deploys)
  assert_eq(out.members, ["paused()"])
  assert_eq(out.skipped.join("\n"), "")
}

///|
/// A constructor taking a type this generator does not translate costs the
/// `deploy` and nothing else — the same judgement `function_block` makes, said
/// about the one member that cannot be reached through
/// `@contract.Contract::call` afterwards.
test "read: a constructor this generator cannot type skips only deploy" {
  let out = @codegen.generate(
    "Blob",
    (
      #|{
      #|  "abi": [
      #|    { "type": "constructor", "stateMutability": "nonpayable",
      #|      "inputs": [{ "name": "salt", "type": "bytes32" }] },
      #|    { "type": "function", "name": "paused", "stateMutability": "view",
      #|      "inputs": [], "outputs": [{ "name": "", "type": "bool" }] }
      #|  ],
      #|  "bytecode": "0x6001"
      #|}
    ),
  )
  assert_false(out.deploys)
  assert_eq(out.members, ["paused()"])
  assert_eq(out.skipped, [
    "`constructor(bytes32)`: parameter 0 is `bytes32`, which is not generated — so no `deploy` was either; `creation_code()` still is, for `@contract.deploy`",
  ])
  // precisely the caller who has to deploy by hand, so the bytes stay
  assert_true(out.code.contains("pub fn Blob::creation_code() -> @types.Hex {"))
  assert_false(out.code.contains("Blob::deploy("))
}

///|
/// A `bytecode` that is not a string is a document no compiler wrote, so it
/// stops the file rather than costing it a `deploy` — the same line every other
/// wrong-typed field in an ABI is held to.
test "read: a bytecode that is not a string raises" {
  try
    @codegen.generate(
      "Foo",
      (
        #|{ "abi": [], "bytecode": 6001 }
      ),
    )
  catch {
    e =>
      inspect(e, content="InvalidAbi(this artifact's bytecode is not a string)")
  } noraise {
    _ => fail("expected a numeric bytecode to raise")
  }
}

///|
/// A contract has one constructor. Two is not something a compiler emits, and
/// letting the last one win would encode the wrong arguments into a deployment
/// that cannot be re-run — so it is refused rather than resolved.
test "read: two constructors raise" {
  try
    @codegen.generate(
      "Twice",
      (
        #|{ "abi": [
        #|  { "type": "constructor", "inputs": [{ "name": "a", "type": "uint256" }] },
        #|  { "type": "constructor", "inputs": [{ "name": "b", "type": "address" }] }
        #|], "bytecode": "0x6001" }
      ),
    )
  catch {
    e =>
      inspect(
        e,
        content="InvalidAbi(this ABI declares more than one constructor)",
      )
  } noraise {
    _ => fail("expected two constructors to raise")
  }
}

///|
/// A pre-0.6 ABI says `payable: true` where a later one says
/// `stateMutability`, and a constructor is where that mattered most: getting it
/// wrong drops the ether a deployment was funded with.
test "read: a pre-0.6 constructor still says it is payable" {
  let out = @codegen.generate(
    "Old",
    (
      #|{ "abi": [{ "type": "constructor", "payable": true, "inputs": [] }],
      #|  "bytecode": "0x6001" }
    ),
  )
  assert_true(out.code.contains("  value? : @types.Wei,\n"))
}

///|
/// A constructor is read now, so a constructor no compiler could have emitted
/// stops the document exactly as a function's would: the file is not an ABI, and
/// nothing else in it is more trustworthy than that entry.
test "read: a constructor declaring a type that cannot exist raises" {
  try
    @codegen.generate(
      "Odd",
      (
        #|{ "abi": [{ "type": "constructor", "inputs": [
        #|  { "name": "n", "type": "uint7" }] }], "bytecode": "0x6001" }
      ),
    )
  catch {
    e => assert_true(e is InvalidAbi(_))
  } noraise {
    _ => fail("expected `uint7` in a constructor to raise")
  }
}

///|
/// A contract's `error` declarations become the array `new` reads a revert
/// against — the one part of an ABI nothing else in the generated file states,
/// since a revert names its error by selector and no call declares what it may
/// fail with.
test "generate: the errors a contract declares are generated" {
  let abi =
    #|[
    #|  { "type": "error", "name": "InsufficientBalance", "inputs": [
    #|    { "name": "have", "type": "uint256" },
    #|    { "name": "want", "type": "uint256" }] },
    #|  { "type": "error", "name": "Unauthorized", "inputs": [] }
    #|]
  let out = @codegen.generate("Vault", abi)
  assert_true(
    out.code.contains(
      "pub fn Vault::errors() -> Array[@contract.ErrorDef] {\n" +
      "  [\n" +
      "    { name: \"InsufficientBalance\", inputs: [Uint(256), Uint(256)] },\n" +
      "    { name: \"Unauthorized\", inputs: [] },\n" +
      "  ]\n" +
      "}\n",
    ),
  )
  // and `new` hands them over, which is what makes a revert decode itself
  assert_true(
    out.code.contains(
      "@contract.Contract::new(address, errors=Vault::errors())",
    ),
  )
  // an error is not a method: nothing dispatches to it, and nothing was skipped
  assert_eq(out.members, [])
  assert_eq(out.skipped, [])
}

///|
/// An error carries every type the ABI has, including the ones no generated
/// *call* may name: nothing is passed to it and nothing is read back out of it
/// as a MoonBit value, so the reason `scalar` draws its line does not apply.
/// Leaving them out would drop exactly the errors that say most about what went
/// wrong.
test "generate: an error declares types no call would" {
  let abi =
    #|[
    #|  { "type": "error", "name": "BadProof", "inputs": [
    #|    { "name": "root", "type": "bytes32" },
    #|    { "name": "proof", "type": "bytes" },
    #|    { "name": "path", "type": "uint256[]" },
    #|    { "name": "pair", "type": "address[2]" },
    #|    { "name": "leaf", "type": "tuple", "components": [
    #|      { "name": "at", "type": "uint64" },
    #|      { "name": "who", "type": "address" }] }] }
    #|]
  let out = @codegen.generate("Merkle", abi)
  assert_true(
    out.code.contains(
      "      inputs: [FixedBytes(32), Bytes, Array(Uint(256)), FixedArray(Address, 2), Tuple([Uint(64), Address])],\n",
    ),
  )
}

///|
/// A document with no `error` in it generates no `errors()`, and its `new` is
/// the one it always was.
test "generate: a contract that declares no error says nothing about errors" {
  let out = @codegen.generate("Erc20", erc20_abi)
  assert_false(out.code.contains("errors"))
  assert_true(out.code.contains("@contract.Contract::new(address)"))
}

///|
/// `errors` is the template's name whether or not the document filled it in,
/// for the reason `deploy` and `creation_code` are: the same ABI must generate
/// the same members however it arrives.
test "generate: a function cannot take the name errors" {
  let abi =
    #|[
    #|  { "type": "function", "name": "errors", "stateMutability": "view",
    #|    "inputs": [], "outputs": [{ "name": "", "type": "uint256" }] }
    #|]
  let out = @codegen.generate("Odd", abi)
  assert_eq(out.members, [])
  assert_eq(out.skipped.length(), 1)
  assert_true(out.skipped[0].contains("`errors` is already taken"))
}
