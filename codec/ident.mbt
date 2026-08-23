///|
/// Whether a string is spelled as a Solidity identifier: a letter, `_` or `$`,
/// and then letters, digits and the same.
///
/// A name that is not one carries characters that mean something wherever it is
/// written out — `,`, `(`, `)` in a signature, quotes in generated source — so
/// two such strings can agree while the names differ. Asked before joining.
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
