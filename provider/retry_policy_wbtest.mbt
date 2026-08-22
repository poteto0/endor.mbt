///|
/// The numbers pinned where changing them fails a test, not only a release
/// note.
test "the default policy is viem's numbers" {
  let policy = RetryPolicy::default()
  assert_eq(policy.max_retry, 3)
  guard policy.strategy is ExponentialDelay(initial~, factor~, maximum~) else {
    fail("the default backs off exponentially")
  }
  assert_eq(initial, 150)
  assert_eq(factor, 2.0)
  assert_eq(maximum, 2_000)
}

///|
test "new defaults whatever it is not told" {
  let counted = RetryPolicy::new(max_retry=5)
  assert_eq(counted.max_retry, 5)
  assert_true(counted.strategy is ExponentialDelay(initial=150, ..))
  let quick = RetryPolicy::new(strategy=Immediate)
  assert_true(quick.strategy is Immediate)
  assert_eq(quick.max_retry, 3)
}

///|
test "none is no second attempt" {
  assert_eq(RetryPolicy::none().max_retry, 0)
}

///|
test "a negative max_retry is none" {
  assert_eq(RetryPolicy::new(max_retry=-1).max_retry, 0)
}
