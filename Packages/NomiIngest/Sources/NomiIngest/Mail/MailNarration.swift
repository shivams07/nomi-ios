import Foundation

/// The raw narration an email carries, and nothing more.
///
/// **This unit does not parse UPI narrations** (§2.4). It emits the narration
/// verbatim and U4's `DraftDerivation` derives `merchantName`, `upiKindRaw` and
/// `counterpartyVPA` from it. An ingester that fills those in is the bug the
/// pipeline asserts against.
///
/// Why a narration extract rather than the whole body: `normalizedDescription`
/// is derived from `descriptionText`, and it is what both dedupe tiers match on.
/// A whole email body would never resemble the same transaction's CSV row
/// closely enough for the ±2-day near-match to fire, so the primary
/// cross-source dedupe AC would fail on exactly the transactions that arrive
/// twice. The UPI reference below is the strongest join available, because it is
/// the same string the bank puts in the statement export.
public enum MailNarration {
  private static let maxLength = 160

  /// A `UPI/...`, `UPI-...` or bare-VPA run — the token a net-banking CSV also
  /// carries for the same transaction.
  private static let upiPattern =
    #"\bUPI[/-][^\s]*(?:\s[^\s]*){0,6}"#
    + #"|\b[A-Za-z0-9._-]{2,}@(?:ok[a-z]+|[a-z]{3,}bank|paytm|ybl|axl|upi)\b"#

  private static let amountAnchorPattern = #"(?:₹|\bINR\b|\bRs\.?)\s*[0-9]"#

  /// §1.4's "merchant from narration heuristics", for Layer 2 — which by
  /// definition has no pack regex to fall back on. Indian alert mail labels the
  /// counterparty with one of a small set of words.
  private static let merchantPattern =
    #"(?:\bInfo:?|\bat\b|\btowards\b|\bto VPA\b)\s+([A-Za-z0-9@._\-/ ]{3,60}?)(?:\s+on\b|[.;]|$)"#

  /// Best available narration, in preference order: a UPI reference, then the
  /// pack's own regex, then the clause around the amount, then the subject.
  ///
  /// The UPI reference outranks the pack's merchant capture on purpose. A pack
  /// regex typically yields the merchant alone (`SWIGGY`), which is tidier to
  /// read and useless as a join — the net-banking CSV for the same transaction
  /// carries `UPI-SWIGGY-swiggy@ybl-622104477311`, and `SWIGGY` will not reach
  /// the 0.9 similarity the near-match tier needs. Preferring the reference
  /// costs nothing except prettiness and is what lets an email and a statement
  /// row for one payment actually merge.
  public static func narration(in text: String, packRegex: String?, subject: String) -> String {
    if let upi = firstMatch(upiPattern, in: text) {
      return clamp(upi)
    }
    if let fromPack = SenderPackFieldRegexes.capture(packRegex, in: text),
      !fromPack.trimmingCharacters(in: .whitespaces).isEmpty
    {
      return clamp(fromPack)
    }
    if let merchant = SenderPackFieldRegexes.capture(merchantPattern, in: text),
      !merchant.trimmingCharacters(in: .whitespaces).isEmpty
    {
      return clamp(merchant)
    }
    if let clause = clauseAroundFirstAmount(in: text) {
      return clamp(clause)
    }
    let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSubject.isEmpty {
      return clamp(trimmedSubject)
    }
    return clamp(boundedWindow(in: text))
  }

  /// The sentence the amount sits in. Bank alerts are one sentence per fact, so
  /// this lands on "Rs 4,500.00 has been debited … at SWIGGY" and leaves the
  /// running-balance sentence behind.
  static func clauseAroundFirstAmount(in text: String) -> String? {
    guard let amountRange = firstAmountAnchorRange(in: text) else { return nil }
    let clause = text[clauseBounds(around: amountRange, in: text)]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return clause.isEmpty ? nil : clause
  }

  /// Where the first `Rs`/`INR`/`\u{20B9}` + digit run sits.
  static func firstAmountAnchorRange(in text: String) -> Range<String.Index>? {
    guard let regex = try? NSRegularExpression(
      pattern: amountAnchorPattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    else { return nil }
    return Range(match.range, in: text)
  }

  /// What ends a clause. Shared with `MailAmount`, which needs the same answer
  /// to a different question — the amount rule and the narration rule both turn
  /// on "is this number in the same clause as the verb", and two private copies
  /// of this set would be two chances to disagree.
  ///
  /// The newline is in here because `MailHTML.plainText` now puts one at every
  /// block boundary. Before it did, a two-cell alert was a single clause and the
  /// running balance sat inside it.
  static let clauseTerminators: Set<Character> = [".", "!", "?", ";", "\n"]

  /// The clause a range sits in, grown outwards to the nearest terminator on
  /// each side.
  static func clauseBounds(
    around range: Range<String.Index>, in text: String
  ) -> Range<String.Index> {
    var start = range.lowerBound
    while start > text.startIndex {
      let previous = text.index(before: start)
      if isClauseTerminator(at: previous, in: text) { break }
      start = previous
    }

    var end = range.upperBound
    while end < text.endIndex {
      if isClauseTerminator(at: end, in: text) { break }
      end = text.index(after: end)
    }

    return start..<end
  }

  /// Every clause, in order. Empty ones — the run of newlines a nested table
  /// leaves behind — are dropped rather than returned as empty ranges.
  static func clauses(in text: String) -> [Range<String.Index>] {
    var result: [Range<String.Index>] = []
    var start = text.startIndex
    var index = text.startIndex

    while index < text.endIndex {
      if isClauseTerminator(at: index, in: text) {
        if start < index { result.append(start..<index) }
        start = text.index(after: index)
      }
      index = text.index(after: index)
    }
    if start < text.endIndex { result.append(start..<text.endIndex) }
    return result
  }

  /// A hard-bounded window around the first amount, for the one case with
  /// neither a bounded clause nor a subject.
  ///
  /// The fallback here used to be `clamp(text)` — the entire body, truncated to
  /// 160 characters. `normalizedDescription` is derived from this string and
  /// both dedupe tiers match on it, so a body-shaped narration makes every mail
  /// from one bank resemble every other: the near-match tier ends up comparing
  /// footer boilerplate and finding it similar. A window is smaller than the
  /// clamp and centred on the only span known to be about a transaction.
  private static func boundedWindow(in text: String) -> String {
    let radius = 60
    guard let anchor = firstAmountAnchorRange(in: text) else {
      return String(text.prefix(radius))
    }
    let start =
      text.index(anchor.lowerBound, offsetBy: -radius, limitedBy: text.startIndex)
      ?? text.startIndex
    let end =
      text.index(anchor.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
    return String(text[start..<end])
  }

  /// A terminator only where it actually ends something.
  ///
  /// `.` is the whole difficulty. It is the sentence end, AND the decimal point
  /// in `4,500.00`, AND the abbreviation dot in `Rs.3,275.50` — and the rule
  /// this replaced only knew about the middle one. It asked "are there digits on
  /// both sides", so the dot in `Rs.3` was a clause boundary and the amount
  /// ended up in a different clause from its own verb. Every Indian alert that
  /// writes `Rs.` rather than `Rs ` hit that, which is most of them, and the
  /// symptom was invisible: the amount rule quietly fell through to its
  /// first-amount fallback and was right for the wrong reason.
  ///
  /// So: a period ends a clause only when whitespace or the end of the text
  /// follows it. That covers all three cases with one question. The other
  /// terminators are unambiguous and always end a clause.
  private static func isClauseTerminator(at index: String.Index, in text: String) -> Bool {
    let character = text[index]
    guard clauseTerminators.contains(character) else { return false }
    guard character == "." else { return true }
    let next = text.index(after: index)
    guard next < text.endIndex else { return true }
    return text[next].isWhitespace
  }

  private static func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
      let range = Range(match.range, in: text)
    else { return nil }
    return String(text[range])
  }

  private static func clamp(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
