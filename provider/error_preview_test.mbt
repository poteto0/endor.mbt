///|
/// A body short enough to read is quoted whole: the messages that carry one are
/// about what came back, and a proxy's one-line notice *is* the answer.
test "a short body is quoted as it came" {
  inspect(
    @provider.body_preview("<html>502 Bad Gateway</html>"),
    content="<html>502 Bad Gateway</html>",
  )
  inspect(@provider.body_preview(""), content="")
  let exact = "x".repeat(@provider.BODY_PREVIEW_CHARS)
  assert_eq(@provider.body_preview(exact), exact)
}

///|
/// Past that, the head and how much there was. A node answering with a
/// megabyte must not become a megabyte of log, and what is cut away is the
/// part that echoes the call back.
test "a long body is cut to its head" {
  let body = "x".repeat(@provider.BODY_PREVIEW_CHARS + 1)
  assert_eq(
    @provider.body_preview(body),
    "\{"x".repeat(@provider.BODY_PREVIEW_CHARS)}… (\{@provider.BODY_PREVIEW_CHARS + 1} chars)",
  )
}

///|
/// The cut counts characters, not the code units a String is stored in, so it
/// never lands inside a character that needs two of them.
test "the cut is by character" {
  let body = "🙈".repeat(@provider.BODY_PREVIEW_CHARS + 1)
  assert_eq(
    @provider.body_preview(body),
    "\{"🙈".repeat(@provider.BODY_PREVIEW_CHARS)}… (\{@provider.BODY_PREVIEW_CHARS + 1} chars)",
  )
}
