import Foundation

/// The money bounds for a manual or edited amount, in minor units (paise). R8, I-8.
///
/// One definition for the store guards and the UI gates, so a gate cannot accept
/// an amount the store refuses, or refuse one the store would take.
public enum AmountRules {
  public static let minimumMinor = 1
  /// 10^11 paise, which is ₹1,00,00,00,000.00.
  public static let maximumMinor = 100_000_000_000

  /// A transaction amount: 1 through `maximumMinor`. Zero is not an amount to record.
  public static func isValidTransactionAmount(_ minor: Int) -> Bool {
    (minimumMinor...maximumMinor).contains(minor)
  }

  /// An account's opening balance: either sign, zero included, up to `maximumMinor` in magnitude.
  public static func isValidOpeningBalance(_ minor: Int) -> Bool {
    (-maximumMinor...maximumMinor).contains(minor)
  }
}

/// Thrown by a store that refuses an amount outside `AmountRules`. The store has
/// written nothing when it throws.
public enum AmountValidationError: Error, Sendable, Equatable {
  case outOfRange(amountMinor: Int)
}

/// Why `AmountText.parse` refused a text. R8b, I-8 amendment.
public enum AmountTextRejection: Error, Sendable, Equatable {
  /// Empty, no digit, a character outside the rule, a second decimal separator, or a
  /// grouping character after the decimal separator.
  case notANumber
  /// More than two digits after the decimal separator.
  case tooManyFractionDigits
  /// More than ten significant whole digits, or beyond `maximumMinor`.
  case outOfRange
}

/// Reads amount text typed into a field, in any locale. R8, I-8.
public enum AmountText {
  /// Display filter for an amount field: Unicode decimal digits become ASCII, the
  /// first decimal separator is kept as typed, and everything else is dropped. A
  /// leading "-" survives only when `allowNegative`, and only at index 0.
  public static func filtered(_ text: String, locale: Locale, allowNegative: Bool) -> String {
    let decimals = decimalSeparators(locale)
    var result = ""
    var seenDecimal = false
    for (index, character) in text.enumerated() {
      if let digit = digitValue(character) {
        result.append(String(digit))
      } else if decimals.contains(character) {
        guard !seenDecimal else { continue }
        seenDecimal = true
        result.append(character)
      } else if character == "-" && index == 0 && allowNegative {
        result.append(character)
      }
    }
    return result
  }

  /// Minor units of `text`, or `nil` wherever `parse` refuses it. `parse` is the rule.
  public static func minorUnits(_ text: String, locale: Locale, allowNegative: Bool) -> Int? {
    try? parse(text, locale: locale, allowNegative: allowNegative).get()
  }

  /// Minor units of `text`, or the reason it is refused. It does not filter: callers pass
  /// field text that `filtered` has already produced.
  ///
  /// Checks run in this order and the first failure wins:
  /// 1. a character outside the rule (digits in any script, decimal separators, grouping
  ///    characters, and "-" only at index 0 with `allowNegative`), a second decimal
  ///    separator, or a grouping character after the decimal separator: `.notANumber`;
  /// 2. no digit at all: `.notANumber`;
  /// 3. more than two digits after the decimal separator: `.tooManyFractionDigits`;
  /// 4. more than ten significant whole digits, leading zeros not counted: `.outOfRange`;
  /// 5. a magnitude beyond `AmountRules.maximumMinor`: `.outOfRange`.
  ///
  /// Zero is `.success(0)`; callers decide whether zero is allowed.
  public static func parse(_ text: String, locale: Locale, allowNegative: Bool) -> Result<Int, AmountTextRejection> {
    let decimals = decimalSeparators(locale)
    let grouping = groupingSeparators(locale, decimals: decimals)
    var isNegative = false
    var whole: [Int] = []
    var fraction: [Int] = []
    var seenDecimal = false

    for (index, character) in text.enumerated() {
      if let digit = digitValue(character) {
        if seenDecimal { fraction.append(digit) } else { whole.append(digit) }
      } else if decimals.contains(character) {
        guard !seenDecimal else { return .failure(.notANumber) }
        seenDecimal = true
      } else if grouping.contains(character) {
        // "1.2 5" is not 1.25: grouping after the decimal separator is not a number.
        guard !seenDecimal else { return .failure(.notANumber) }
      } else if character == "-" && index == 0 && allowNegative {
        isNegative = true
      } else {
        return .failure(.notANumber)
      }
    }

    guard !(whole.isEmpty && fraction.isEmpty) else { return .failure(.notANumber) }
    guard fraction.count <= 2 else { return .failure(.tooManyFractionDigits) }
    // Leading zeros are not significant: "00000000001.50" is 150. Checked before any
    // arithmetic, so a long entry is refused rather than wrapped.
    guard whole.drop(while: { $0 == 0 }).count <= 10 else { return .failure(.outOfRange) }

    var rupees = 0
    for digit in whole { rupees = rupees * 10 + digit }
    var paise = 0
    for digit in fraction { paise = paise * 10 + digit }
    if fraction.count == 1 { paise *= 10 }

    let magnitude = rupees * 100 + paise
    guard magnitude <= AmountRules.maximumMinor else { return .failure(.outOfRange) }
    return .success(isNegative ? -magnitude : magnitude)
  }

  /// "." is always a decimal separator. The locale's own, when it is a single
  /// character, is one too.
  private static func decimalSeparators(_ locale: Locale) -> Set<Character> {
    var separators: Set<Character> = ["."]
    if let local = singleCharacter(locale.decimalSeparator) { separators.insert(local) }
    return separators
  }

  /// The locale's grouping separator, "," where "," is not a decimal separator, and
  /// the three spaces. Never a decimal separator.
  private static func groupingSeparators(_ locale: Locale, decimals: Set<Character>) -> Set<Character> {
    var separators: Set<Character> = ["\u{0020}", "\u{00A0}", "\u{202F}"]
    if let local = singleCharacter(locale.groupingSeparator) { separators.insert(local) }
    if !decimals.contains(",") { separators.insert(",") }
    return separators.subtracting(decimals)
  }

  private static func singleCharacter(_ string: String?) -> Character? {
    guard let string, string.count == 1 else { return nil }
    return string.first
  }

  /// The value of a character that is a decimal digit in any script, or `nil`.
  /// Superscripts and vulgar fractions are not decimal digits.
  private static func digitValue(_ character: Character) -> Int? {
    let scalars = character.unicodeScalars
    guard scalars.count == 1, let scalar = scalars.first,
      scalar.properties.numericType == .decimal,
      let value = scalar.properties.numericValue
    else { return nil }
    return Int(value)
  }
}
