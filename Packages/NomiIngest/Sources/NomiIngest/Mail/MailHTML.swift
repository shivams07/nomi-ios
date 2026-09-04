import Foundation
import SwiftSoup

/// HTML to text, before any regex ever runs. R6: Indian bank mail is
/// nested-table HTML, and regexing the raw source produces amounts that are
/// plausible and wrong — the worst failure available here.
///
/// Every pattern below is a raw string literal. Regexes and Swift escape
/// sequences disagree about what `\b` means, and a `#"..."#` literal removes the
/// question.
public enum MailHTML {
  /// The block tags whose end is a real boundary in the text. `<td>` and `<tr>`
  /// carry the weight: two sibling cells — the transaction in one, the running
  /// balance in the next — are how Indian alert mail actually arrives.
  private static let blockTags =
    "p, div, br, table, thead, tbody, tfoot, tr, td, th, li, ul, ol,"
    + " h1, h2, h3, h4, h5, h6, blockquote, section, article, header, footer, pre, hr"

  /// A private-use scalar, inserted at every block boundary and swapped for a
  /// newline once SwiftSoup is done.
  ///
  /// It has to be a non-whitespace character: `text()` collapses whitespace, so
  /// a literal newline handed to SwiftSoup comes back as a space and the
  /// boundary is lost again. This is the whole trick.
  private static let boundary = "\u{E000}"

  /// SwiftSoup's `text()`, with a NEWLINE at every block boundary rather than
  /// the single space `text()` leaves there.
  ///
  /// The space was the defect. `clauseAroundFirstAmount` and the Layer 2 amount
  /// rule both need to know where one cell ends and the next begins, and a
  /// space is indistinguishable from the space between two words — so the
  /// narration ran on into "Available Balance" and the amount rule saw the
  /// running balance as just another number in the same sentence.
  ///
  /// Falls back to a tag strip only if SwiftSoup throws. That fallback is
  /// strictly worse and is here so a malformed message degrades to a
  /// `needsReview` row rather than to nothing at all. It marks the same
  /// boundaries, coarsely.
  public static func plainText(fromHTML html: String) -> String {
    do {
      let document = try SwiftSoup.parse(html)
      try document.select("script, style, head").remove()
      for element in try document.select(blockTags).array() {
        // `br` and `hr` are void: a child text node on them is not something
        // every parser round-trips, so the marker goes after them instead.
        if element.tagName() == "br" || element.tagName() == "hr" {
          try element.after(boundary)
        } else {
          try element.appendText(boundary)
        }
      }
      let marked = try document.text()
      return normalizeWhitespace(marked.replacingOccurrences(of: boundary, with: "\n"))
    } catch {
      var stripped = html.replacingOccurrences(
        of: #"</?(?:p|div|br|table|thead|tbody|tfoot|tr|td|th|li|ul|ol|h[1-6]|blockquote|section|article|header|footer|pre|hr)\b[^>]*>"#,
        with: boundary, options: [.regularExpression, .caseInsensitive]
      )
      stripped = stripped.replacingOccurrences(
        of: #"<[^>]+>"#, with: " ", options: .regularExpression
      )
      return normalizeWhitespace(stripped.replacingOccurrences(of: boundary, with: "\n"))
    }
  }

  /// Non-breaking spaces to real ones (bank mail is full of `&nbsp;`), collapse
  /// horizontal runs, collapse newline runs to ONE newline, then rejoin the two
  /// ways a table splits a number.
  ///
  /// Newlines survive on purpose. Collapsing every `\s+` to a space — which is
  /// what this did — threw away the block boundaries `plainText` had just gone
  /// to the trouble of marking.
  public static func normalizeWhitespace(_ raw: String) -> String {
    var text = raw
    for space in ["\u{00A0}", "\u{2007}", "\u{202F}", "\u{FEFF}"] {
      text = text.replacingOccurrences(of: space, with: " ")
    }
    // Any whitespace run CONTAINING a line break becomes exactly one newline,
    // surrounding spaces included. Runs of blank lines collapse with it.
    text = text.replacingOccurrences(
      of: #"[^\S\r\n]*[\r\n]+\s*"#, with: "\n", options: .regularExpression)
    // What is left has no line breaks in it, so this cannot undo the above.
    text = text.replacingOccurrences(
      of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
    return rejoinSplitDecimals(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// `"4,500 .00"`, `"4,500. 00"` and `"2,349 . 75"` all become the joined
  /// amount. This is R6's failure mode reduced to one rule.
  ///
  /// Deliberately narrow. The obvious general rule — delete any whitespace
  /// between two digit runs — would glue `<td>1,200</td><td>3,400</td>` into
  /// `1,2003,400`, and a statement table of adjacent amounts is at least as
  /// common in real mail as a split one. The pattern below requires a literal
  /// decimal point and a *bare two-digit* fraction that is not followed by
  /// another digit, and neither of those describes a whole number, so it cannot
  /// merge two amounts.
  ///
  /// `\s` covers the newline the cell boundary now leaves behind, which is the
  /// point: the split-decimal shape is *why* those two cells were adjacent.
  ///
  /// It is not free of false positives: `"…on 13-08-2026. 75 units"` would join
  /// to `2026.75`. That needs a sentence to end on a four-digit year and the
  /// next one to open on exactly two digits, and the trade is against silently
  /// dropping the paise off every split amount, which is the far likelier and
  /// far worse error.
  ///
  /// The remaining split — a currency symbol separated from its digits — needs
  /// no rewriting; `MailAmount`'s pattern already allows whitespace there.
  static func rejoinSplitDecimals(_ text: String) -> String {
    text.replacingOccurrences(
      of: #"(?<=[0-9])\s*\.\s*(?=[0-9]{2}(?![0-9]))"#,
      with: ".",
      options: .regularExpression
    )
  }
}
