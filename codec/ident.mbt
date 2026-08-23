///|
/// Whether a string is spelled as a Solidity identifier: a letter, `_` or `$`,
/// and then letters, digits and the same.
///
/// A name that is not one of these is a name carrying characters that mean
/// something wherever it is written out — `,`, `(` and `)` in the strings a
/// signature or an `encodeType` is joined from, quotes and newlines in
/// generated source. Two of those strings can then be made to agree while the
/// names they were built from differ, which is why the question is asked
/// before a name is joined into anything rather than after.
///
/// One pass, no allocation: every character an identifier may hold is ASCII,
/// so nothing here has to look past one.
///
/// ```
/// inspect(@codec.is_solidity_ident("transferFrom"), content="true")
/// inspect(@codec.is_solidity_ident("Mail(address to)"), content="false")
/// ```
pub fn is_solidity_ident(name : String) -> Bool {
  let mut first = true
  for c in name {
    let ok = c.is_ascii_alphabetic() ||
      c == '_' ||
      c == '$' ||
      (!first && c.is_ascii_digit())
    guard ok else { return false }
    first = false
  }
  // `first` is still set when the loop never ran, and the empty string is no
  // more an identifier than a digit is
  !first
}
