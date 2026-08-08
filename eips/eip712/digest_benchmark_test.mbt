///|
/// The spec's `Mail`, with `to` widened to an array so the bench can grow the
/// document without changing its shape.
fn bench_mail_types() -> Map[String, Array[@eip712.TypedDataField]] raise @types.CodecError {
  {
    "Person": [
      @eip712.TypedDataField::new("name", "string"),
      @eip712.TypedDataField::new("wallet", "address"),
    ],
    "Mail": [
      @eip712.TypedDataField::new("from", "Person"),
      @eip712.TypedDataField::new("to", "Person[]"),
      @eip712.TypedDataField::new("contents", "string"),
    ],
  }
}

///|
fn bench_mail_message(recipients : Int) -> Json {
  let to : Array[Json] = Array::makei(recipients, _ => {
    "name": "Bob",
    "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
  })

  {
    "from": {
      "name": "Cow",
      "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
    },
    "to": Json::array(to),
    "contents": "Hello, Bob!",
  }
}

///|
/// The document is assembled outside the timed closure: `TypedData::new`
/// validates the message against its types, and only `digest` is measured.
fn bench_mail(recipients : Int) -> @eip712.TypedData raise @types.CodecError {
  @eip712.TypedData::new(
    mail_domain(),
    primary_type="Mail",
    types=bench_mail_types(),
    message=bench_mail_message(recipients),
  )
}

///|
test "bench: eip712 digest" (b : @bench.T) {
  let one = bench_mail(1) catch { _ => return }
  let many = bench_mail(300) catch { _ => return }
  b.bench(name="Mail", fn() { ignore(one.digest()) catch { _ => () } })
  b.bench(name="Mail x300", fn() { ignore(many.digest()) catch { _ => () } })
}
