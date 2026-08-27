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
    var found: [(location: Int, minor: Int)] = []
    for pattern in [leadingSymbolPattern, trailingSymbolPattern] {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
      else { continue }
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      for match in regex.matches(in: text, range: range) {
        guard match.numberOfRanges > 1,
          let captured = Range(match.range(at: 1), in: text),
          let minor = paise(fromDigits: String(text[captured]))
        else { continue }
        found.append((match.range.location, minor))
      }
    }
    return found.sorted { $0.location < $1.location }.map(\.minor)
  }

  /// The first amount, which for a single-transaction alert is the transaction.
  public static func firstAmount(in text: String) -> Int? {
    allAmounts(in: text).first
  }

  /// Layer 2's rule: the largest currency amount in the message (§1.4).
  ///
  /// It is a heuristic and it is wrong sometimes — a mail quoting both the
  /// charge and the remaining balance yields the balance. That is exactly why
  /// every Layer-2 row is created `needsReview = true` and shows its raw source.
  public static func largestAmount(in text: String) -> Int? {
    allAmounts(in: text).max()
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
