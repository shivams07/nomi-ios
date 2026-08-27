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
  /// SwiftSoup's `text()`, which puts a space between block elements (so two
  /// `<td>`s never run together) and none between inline ones (so a `<span>`
  /// wrapping half an amount does not split it).
  ///
  /// Falls back to a tag strip only if SwiftSoup throws. That fallback is
  /// strictly worse and is here so a malformed message degrades to a
  /// `needsReview` row rather than to nothing at all.
  public static func plainText(fromHTML html: String) -> String {
    do {
      let document = try SwiftSoup.parse(html)
      try document.select("script, style, head").remove()
      return normalizeWhitespace(try document.text())
    } catch {
      let stripped = html.replacingOccurrences(
        of: #"<[^>]+>"#, with: " ", options: .regularExpression
      )
      return normalizeWhitespace(stripped)
    }
  }

  /// Non-breaking spaces to real ones (bank mail is full of `&nbsp;`), then
  /// collapse runs, then rejoin the two ways a table splits a number.
  public static func normalizeWhitespace(_ raw: String) -> String {
    var text = raw
    for space in ["\u{00A0}", "\u{2007}", "\u{202F}", "\u{FEFF}"] {
      text = text.replacingOccurrences(of: space, with: " ")
    }
    text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
