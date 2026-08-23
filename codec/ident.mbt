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
  guard !name.is_empty() else { return false }
  // the one rule that is not the same for every character: a digit is allowed
  // from the second on, never as the first
  let mut digits_allowed = false
  for c in name {
    let ok = c.is_ascii_alphabetic() ||
      c == '_' ||
      c == '$' ||
      (digits_allowed && c.is_ascii_digit())
    guard ok else { return false }
    digits_allowed = true
  }
  true
}
