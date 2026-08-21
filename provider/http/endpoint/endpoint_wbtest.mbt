///|
test "the Retry-After a rate limiter sends is read as seconds" {
  assert_eq(retry_after_seconds({ "retry-after": "30" }), Some(30))
  // whitespace around a header value is not part of it
  assert_eq(retry_after_seconds({ "retry-after": " 5 " }), Some(5))
  assert_eq(retry_after_seconds({ "retry-after": "0" }), Some(0))
}

///|
test "anything that is not plain seconds is left to the backoff" {
  // the header's other form: an HTTP-date, which is not read
  assert_eq(
    retry_after_seconds({ "retry-after": "Wed, 21 Oct 2015 07:28:00 GMT" }),
    None,
  )
  assert_eq(retry_after_seconds({ "retry-after": "" }), None)
  assert_eq(retry_after_seconds({ "retry-after": "-1" }), None)
  assert_eq(retry_after_seconds({ "retry-after": "1.5" }), None)
  // read as seconds, not as the hex the default base would make of it
  assert_eq(retry_after_seconds({ "retry-after": "0x10" }), None)
  // more seconds than an Int holds. How long is *too* long to wait is the
  // retry loop's to say, and it says so on values this reads fine
  assert_eq(retry_after_seconds({ "retry-after": "99999999999" }), None)
  assert_eq(retry_after_seconds({ "content-type": "text/plain" }), None)
}
