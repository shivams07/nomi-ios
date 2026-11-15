import Foundation
import NomiCore

/// Display strings for the Auto-categorise rows (S10; canvas `Rules`). The rows
/// read as sentences: "Blue Tokai", "Spent · HDFC ••4471 · ₹100 to ₹2,000".
/// The glob syntax stays on the Advanced screen, where it is edited.
enum RuleDisplay {
  /// The name a pattern stands for. One leading and one trailing "*" are
  /// stripped and the rest is title-cased word by word ("*BLUE TOKAI*" →
  /// "Blue Tokai"). A pattern that still has a "*" in the middle, or nothing
  /// left once the ends are stripped ("*"), is returned unchanged: it is not
  /// a plain merchant name, and guessing one would hide what the rule matches.
  static func title(pattern: String) -> String {
    var core = Substring(pattern)
    if core.hasPrefix("*") { core = core.dropFirst() }
    if core.hasSuffix("*") { core = core.dropLast() }
    guard !core.isEmpty, !core.contains("*") else { return pattern }
    return core
      .split(separator: " ", omittingEmptySubsequences: false)
      .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
      .joined(separator: " ")
  }

  /// The row's second line: direction, account and amount, joined " · ", or
  /// "Any payment" when the scope has none of them.
  ///
  /// `accountName` returns the label to show for an account (see
  /// `accountLabel(institution:lastFour:)`); nil, or an empty label, shows
  /// "Unknown account", as the account is gone or was never loaded.
  static func scopeLine(_ scope: RuleScope, accountName: (UUID) -> String?) -> String {
    var parts: [String] = []
    if let direction = scope.direction {
      parts.append(direction == .debit ? "Spent" : "Income")
    }
    if let accountID = scope.accountID {
      let label = accountName(accountID).flatMap { $0.isEmpty ? nil : $0 }
      parts.append(label ?? "Unknown account")
    }
    switch (scope.minAmountMinor, scope.maxAmountMinor) {
    case let (.some(minAmount), .some(maxAmount)):
      parts.append("\(wholeRupees(minAmount)) to \(wholeRupees(maxAmount))")
    case let (.some(minAmount), nil):
      parts.append("\(wholeRupees(minAmount)) or more")
    case let (nil, .some(maxAmount)):
      parts.append("Up to \(wholeRupees(maxAmount))")
    case (nil, nil):
      break
    }
    return parts.isEmpty ? "Any payment" : parts.joined(separator: " · ")
  }

  /// "HDFC ••4471" from an account's institution and last four. A missing last
  /// four (a wallet) leaves the institution alone, as `AccountRowText` does.
  static func accountLabel(institution: String, lastFour: String) -> String {
    let maskedLastFour = lastFour.isEmpty ? "" : "••\(lastFour)"
    return [institution, maskedLastFour].filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Whether a row stays on screen for the search field (S10). Matches the
  /// title or the category name, ignoring case. A blank query matches every row.
  static func matchesSearch(_ query: String, title: String, categoryName: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return true }
    return title.localizedCaseInsensitiveContains(needle)
      || categoryName.localizedCaseInsensitiveContains(needle)
  }

  /// Whole rupees, as the scope line states amounts. Paise are dropped, not
  /// rounded, the same as the app's other amount copy.
  private static func wholeRupees(_ minor: Int) -> String {
    let rupees = minor / 100
    return wholeRupeeFormatter.string(from: NSNumber(value: rupees)) ?? "₹\(rupees)"
  }

  private static let wholeRupeeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter
  }()
}
