///|
/// A URL cut into the four parts this package decides anything about.
///
/// A cut, not a parse: `validate_http_url` is what says a string is a URL, and a
/// string that is none is cut by the same rules so `display_url` can name it
/// back. `scheme` is `None` when there is no `://`, `userinfo` is dropped here
/// because it is a credential, and the fragment never leaves the client.
priv struct UrlParts {
  scheme : String?
  authority : String
  path : String
  query : String?
}

///|
/// Cut `url` at its delimiters, in the order a URL nests them: the fragment
/// ends the query, the query ends the path, and the path ends the authority.
fn split_url(url : String) -> UrlParts {
  let (scheme, rest) = match url.split_once("://") {
    Some((scheme, rest)) => (Some(scheme.to_owned()), rest)
    None => (None, url[:])
  }
  let rest = match rest.split_once("#") {
    Some((head, _)) => head
    None => rest
  }
  let (rest, query) = match rest.split_once("?") {
    Some((head, query)) => (head, Some(query.to_owned()))
    None => (rest, None)
  }
  let (authority, path) = match rest.split_once("/") {
    Some((authority, path)) => (authority, "/\{path}")
    None => (rest, "")
  }
  // the authority runs to the first delimiter; a `@` means everything before
  // it was credentials, and the host starts after the last one
  let authority = match authority.rev_split_once("@") {
    Some((_, host)) => host
    None => authority
  }
  UrlParts::{ scheme, authority: authority.to_owned(), path, query }
}
