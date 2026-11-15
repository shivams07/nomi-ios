import Foundation
import NomiCore

/// The glob "Always use this for <merchant>" writes on Transaction detail (S3a).
/// Pure, so the pattern a row would get can be tested without a store or a view.
///
/// A merchant name wins when it normalises to at least three characters. Otherwise
/// the pattern is the first two words of the bank text that are not a payment rail
/// (UPI, NEFT, IMPS, RTGS, POS, ATM) and carry no digit, which is a guess for
/// rows the merchant name does not cover.
public enum MerchantRulePattern {
  private static let rails: Set<String> = ["UPI", "NEFT", "IMPS", "RTGS", "POS", "ATM"]

  /// `*<MERCHANT>*` for a usable merchant name, else `*<WORD WORD>*` from the bank
  /// text, else nil when neither gives a word.
  public static func pattern(merchantName: String?, normalizedDescription: String) -> String? {
    if let merchant = usableMerchant(merchantName) {
      return "*\(normalizeDescription(merchant))*"
    }
    let words = fallbackWords(normalizedDescription)
    guard !words.isEmpty else { return nil }
    return "*\(words.joined(separator: " "))*"
  }

  /// The merchant name as the user knows it when one is usable, else the same
  /// fallback words title-cased. Follows the pattern's branch, so a name that is
  /// too short to pattern is not shown as the merchant.
  public static func displayName(merchantName: String?, normalizedDescription: String) -> String {
    if let merchant = usableMerchant(merchantName) {
      return merchant
    }
    return fallbackWords(normalizedDescription).map(titleCase).joined(separator: " ")
  }

  /// The trimmed name, when it normalises to at least three characters.
  private static func usableMerchant(_ name: String?) -> String? {
    guard let name else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizeDescription(trimmed).count >= 3 else { return nil }
    return trimmed
  }

  /// The first two words that are not a rail and carry no digit.
  private static func fallbackWords(_ normalized: String) -> [String] {
    normalized
      .split(separator: " ")
      .map(String.init)
      .filter { word in !rails.contains(word) && !word.contains(where: { $0.isNumber }) }
      .prefix(2)
      .map { $0 }
  }

  /// First letter upper, the rest lower: "SBI" becomes "Sbi".
  private static func titleCase(_ word: String) -> String {
    word.prefix(1).uppercased() + word.dropFirst().lowercased()
  }
}
