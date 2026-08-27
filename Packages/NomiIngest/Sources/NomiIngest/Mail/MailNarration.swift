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
    return clamp(subject.isEmpty ? text : subject)
  }

  /// The sentence the amount sits in. Bank alerts are one sentence per fact, so
  /// this lands on "Rs 4,500.00 has been debited … at SWIGGY" and leaves the
  /// running-balance sentence behind.
  static func clauseAroundFirstAmount(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(
      pattern: amountAnchorPattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
      let amountRange = Range(match.range, in: text)
    else { return nil }

    let terminators: Set<Character> = [".", "!", "?", ";", "\n"]

    var start = amountRange.lowerBound
    while start > text.startIndex {
      let previous = text.index(before: start)
      // Do not split on the decimal point inside the amount itself.
      if terminators.contains(text[previous]), !isDecimalPoint(at: previous, in: text) { break }
      start = previous
    }

    var end = amountRange.upperBound
    while end < text.endIndex {
      if terminators.contains(text[end]), !isDecimalPoint(at: end, in: text) { break }
      end = text.index(after: end)
    }

    let clause = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    return clause.isEmpty ? nil : clause
  }

  private static func isDecimalPoint(at index: String.Index, in text: String) -> Bool {
    guard text[index] == "." else { return false }
    guard index > text.startIndex else { return false }
    let next = text.index(after: index)
    guard next < text.endIndex else { return false }
    return text[text.index(before: index)].isNumber && text[next].isNumber
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
