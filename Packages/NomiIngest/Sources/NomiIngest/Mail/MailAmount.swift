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

  // MARK: - Foreign currency (U18 / M9)

  /// A currency amount that is not INR.
  ///
  /// `minor` is in **that currency's** minor unit, not paise. There is no rate
  /// source in this app and none is guessed, so the number is only ever shown
  /// beside its code and never added to a rupee total.
  public struct ForeignAmount: Equatable, Sendable {
    public let currencyCode: String
    public let minor: Int

    public init(currencyCode: String, minor: Int) {
      self.currencyCode = currencyCode
      self.minor = minor
    }
  }

  /// The codes recognised, and how many digits each one's minor unit has.
  ///
  /// The exponent is not decoration. JPY and KRW have **no** minor unit: ¥1000
  /// is 1000 minor units, not 100000. Scaling every currency by 100 would put a
  /// hundred-fold error on a row the user is being asked to confirm, which is
  /// exactly the "plausible wrong number" R6 ranks worst. Currencies whose
  /// exponent is neither 0 nor 2 (KWD, BHD) are deliberately absent rather than
  /// mis-scaled.
  static let foreignCurrencies: [String: Int] = [
    "USD": 2, "EUR": 2, "GBP": 2, "AED": 2, "SGD": 2,
    "AUD": 2, "CAD": 2, "CHF": 2, "JPY": 0, "KRW": 0,
  ]

  /// Symbols worth honouring. `$` is ambiguous across a dozen currencies; it is
  /// read as USD because that is what an Indian card statement means by it, and
  /// the row is flagged for a human either way.
  private static let currencySymbols: [String: String] = [
    "US$": "USD", "$": "USD", "€": "EUR", "£": "GBP",
  ]

  private static let codeAlternation = foreignCurrencies.keys.sorted().joined(separator: "|")

  private static let numberPattern = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![0-9])"#

  /// The first non-INR amount in the text, by position.
  ///
  /// Deliberately independent of `firstAmount`: a mail carrying both — "₹1,089.00
  /// (USD 12.99)" on a card statement — is an INR transaction, and the caller
  /// asks for the rupee amount first. This only answers "was there a foreign
  /// amount", never "which amount is the transaction".
  public static func foreignAmount(in text: String) -> ForeignAmount? {
    foreignAmountsWithRanges(in: text).first?.amount
  }

  static func foreignAmountsWithRanges(in text: String)
    -> [(range: Range<String.Index>, amount: ForeignAmount)]
  {
    // Three patterns rather than one with optional groups: the capture indices
    // stay fixed, which is the part of a combined pattern that goes wrong
    // silently when someone edits it later.
    let symbolAlternation =
      currencySymbols.keys
      .sorted { $0.count > $1.count }  // "US$" before "$", or "$" wins and eats it
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")

    let specs: [(pattern: String, codeGroup: Int, digitsGroup: Int, isSymbol: Bool)] = [
      (#"\b(\#(codeAlternation))\b\s*\#(numberPattern)"#, 1, 2, false),
      (#"(\#(symbolAlternation))\s*\#(numberPattern)"#, 1, 2, true),
      (#"\#(numberPattern)\s*\b(\#(codeAlternation))\b"#, 2, 1, false),
    ]

    var found: [(range: Range<String.Index>, amount: ForeignAmount)] = []
    for spec in specs {
      guard
        let regex = try? NSRegularExpression(pattern: spec.pattern, options: [.caseInsensitive])
      else { continue }
      let full = NSRange(text.startIndex..<text.endIndex, in: text)
      for match in regex.matches(in: text, range: full) {
        guard let whole = Range(match.range, in: text),
          let codeRange = Range(match.range(at: spec.codeGroup), in: text),
          let digitsRange = Range(match.range(at: spec.digitsGroup), in: text)
        else { continue }

        let token = String(text[codeRange])
        let code =
          spec.isSymbol
          ? currencySymbols[token.uppercased()] : token.uppercased()
        guard let code, let exponent = foreignCurrencies[code],
          let minor = minorUnits(fromDigits: String(text[digitsRange]), exponent: exponent)
        else { continue }

        found.append((whole, ForeignAmount(currencyCode: code, minor: minor)))
      }
    }
    return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
  }

  /// Digits to minor units for a currency with `exponent` minor digits.
  ///
  /// `exponent == 2` is `paise(fromDigits:)`. `exponent == 0` rejects any
  /// fractional part outright: "JPY 1000.50" is not a yen amount, and rounding
  /// it would invent a number.
  static func minorUnits(fromDigits raw: String, exponent: Int) -> Int? {
    switch exponent {
    case 2:
      return paise(fromDigits: raw)
    case 0:
      let cleaned = raw.replacingOccurrences(of: ",", with: "")
        .trimmingCharacters(in: .whitespaces)
      guard !cleaned.contains("."), !cleaned.isEmpty, let value = Int(cleaned) else { return nil }
      return value
    default:
      return nil
    }
  }
}
