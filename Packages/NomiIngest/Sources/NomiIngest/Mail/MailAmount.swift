import Foundation

/// Currency amounts out of normalized mail text, as `Int` paise.
///
/// No `Double` anywhere in the conversion — R9. `"4,500.75"` becomes `450075`
/// by integer arithmetic on the two halves, not by parsing a decimal and
/// multiplying by 100.
public enum MailAmount {
  /// `₹`, `INR`, `Rs`, `Rs.` — the four forms §1.4 names — then optional
  /// whitespace, then the number. That whitespace is what lets a currency symbol
  /// in one table cell find its digits in the next.
  private static let leadingSymbolPattern = #"(?:₹|\bINR\b|\bRs\.?)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![0-9])"#

  /// The trailing form: `4,500.00 INR`. Less common, but some UPI alerts use it.
  private static let trailingSymbolPattern = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:₹|\bINR\b)(?![A-Za-z])"#

  /// Every amount in the text, in the order they appear. Deduplicated by
  /// position rather than by value — two ₹500 charges in one mail are two
  /// amounts, not one.
  public static func allAmounts(in text: String) -> [Int] {
    amountsWithRanges(in: text).map(\.minor)
  }

  /// The same amounts, each with the span it was matched in. The Layer 2 rule
  /// needs to know WHERE a number is, not just what it is.
  static func amountsWithRanges(in text: String) -> [(range: Range<String.Index>, minor: Int)] {
    var found: [(range: Range<String.Index>, minor: Int)] = []
    for pattern in [leadingSymbolPattern, trailingSymbolPattern] {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
      else { continue }
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      for match in regex.matches(in: text, range: range) {
        guard match.numberOfRanges > 1,
          let whole = Range(match.range, in: text),
          let captured = Range(match.range(at: 1), in: text),
          let minor = paise(fromDigits: String(text[captured]))
        else { continue }
        found.append((whole, minor))
      }
    }
    return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
  }

  /// The first amount, which for a single-transaction alert is the transaction.
  public static func firstAmount(in text: String) -> Int? {
    allAmounts(in: text).first
  }

  /// Layer 2's rule: the amount in the same clause as the direction verb,
  /// nearest to it. `verbRange` is the span the caller found that verb in.
  ///
  /// This replaces largest-wins (§1.4), which was not merely "wrong sometimes"
  /// — it was wrong on the commonest shape in Indian alert mail. A mail that
  /// quotes the running balance beside the charge always has a larger balance
  /// than charge, so largest-wins picked the balance every time, and
  /// `needsReview` does not redeem that: a plausible wrong number is the one
  /// failure R6 ranks worst, because a user skimming the review queue accepts
  /// it. "Rs.48,900.00 at IRCTC" reads as a real transaction. Zero does not.
  ///
  /// Falls back to the FIRST amount, not the largest, when there is no verb
  /// clause or no amount inside it. A single-transaction alert leads with its
  /// amount, and being wrong towards the first number at least fails the same
  /// way every time.
  public static func transactionAmount(in text: String, verbRange: Range<String.Index>?)
    -> Int?
  {
    let amounts = amountsWithRanges(in: text)
    guard !amounts.isEmpty else { return nil }
    guard let verbRange else { return amounts.first?.minor }

    let clause = MailNarration.clauseBounds(around: verbRange, in: text)
    let inClause = amounts.filter { clause.contains($0.range.lowerBound) }
    guard !inClause.isEmpty else { return amounts.first?.minor }

    return inClause.min {
      characterDistance(from: $0.range, to: verbRange, in: text)
        < characterDistance(from: $1.range, to: verbRange, in: text)
    }?.minor
  }

  /// Characters between two spans, zero if they overlap.
  private static func characterDistance(
    from range: Range<String.Index>, to other: Range<String.Index>, in text: String
  ) -> Int {
    if range.upperBound <= other.lowerBound {
      return text.distance(from: range.upperBound, to: other.lowerBound)
    }
    if other.upperBound <= range.lowerBound {
      return text.distance(from: other.upperBound, to: range.lowerBound)
    }
    return 0
  }

  /// `"4,500.75"` -> `450075`. `"4,500.7"` -> `450070`. `"4,500"` -> `450000`.
  ///
  /// Integer only. Overflow returns nil rather than trapping: a malformed mail
  /// carrying a forty-digit run must produce a `needsReview` row, not a crash in
  /// a background sync the user cannot see.
  static func paise(fromDigits raw: String) -> Int? {
    let cleaned = raw.replacingOccurrences(of: ",", with: "")
      .trimmingCharacters(in: .whitespaces)
    let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let rupeePart = parts.first, !rupeePart.isEmpty, let rupees = Int(rupeePart) else {
      return nil
    }

    var fraction = 0
    if parts.count == 2 {
      let digits = String(parts[1])
      guard digits.count <= 2, !digits.isEmpty, digits.allSatisfy(\.isNumber),
        let value = Int(digits)
      else { return nil }
      fraction = digits.count == 1 ? value * 10 : value
    }

    let (scaled, overflowed) = rupees.multipliedReportingOverflow(by: 100)
    guard !overflowed else { return nil }
    let (total, addOverflowed) = scaled.addingReportingOverflow(fraction)
    guard !addOverflowed else { return nil }
    return total
  }
}
