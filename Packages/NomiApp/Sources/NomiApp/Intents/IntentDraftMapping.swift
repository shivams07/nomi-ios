import Foundation
import NomiCore

/// Turns what Siri or the Shortcuts app collected into a `ManualTransactionDraft`.
///
/// Pure, and separate from `AddTransactionIntent`, because an `AppIntent` is
/// not something `swift test` can run — it needs the intents runtime and a
/// host app. Every decision worth testing therefore lives here and the intent
/// is left as wiring.
public enum IntentDraftMapping {

  public enum Failure: Error, Equatable {
    /// More than two fraction digits. Rupees have two, and rounding someone's
    /// amount for them is how a ledger stops reconciling with a bank statement.
    case tooPrecise
    /// Zero, negative, or larger than the app can represent.
    case outOfRange
    case blankDescription
  }

  /// Rupees to paise, by integer arithmetic on `Decimal`.
  ///
  /// Not `Int(amount * 100)` through a `Double`: `12.99` is not representable
  /// in binary floating point, and the nearest `Double` times 100 is
  /// 1298.9999999999998, which truncates to 1298. One paisa lost per entry,
  /// silently, forever. `RowMapper` parses file amounts the same way and for
  /// the same reason.
  ///
  /// Rejects rather than rounds: "12.999" is a typo or a currency this app
  /// does not handle, and either way guessing which is worse than declining.
  public static func minorUnits(from amount: Decimal) -> Result<Int, Failure> {
    guard amount > 0 else { return .failure(.outOfRange) }

    var input = amount
    var hundredths = Decimal()
    NSDecimalMultiplyByPowerOf10(&hundredths, &input, 2, .plain)

    var whole = Decimal()
    var copy = hundredths
    NSDecimalRound(&whole, &copy, 0, .plain)
    guard whole == hundredths else { return .failure(.tooPrecise) }

    let number = NSDecimalNumber(decimal: whole)
    guard number.compare(NSDecimalNumber(value: Int.max)) != .orderedDescending else {
      return .failure(.outOfRange)
    }
    let minor = number.intValue
    guard minor > 0 else { return .failure(.outOfRange) }
    return .success(minor)
  }

  /// The whole mapping. `descriptionText` is what the user dictated; it is
  /// stored verbatim, exactly as a bank narration is, and the pipeline derives
  /// `normalizedDescription` and `dedupeKey` from it as for any other row.
  ///
  /// `isIncome` flips the direction rather than accepting a negative amount:
  /// "add minus five hundred" is not a sentence anyone says to Siri.
  public static func draft(
    amount: Decimal,
    note: String?,
    categoryID: UUID?,
    isIncome: Bool,
    now: Date = Date()
  ) -> Result<ManualTransactionDraft, Failure> {
    let description = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else { return .failure(.blankDescription) }

    switch minorUnits(from: amount) {
    case .failure(let failure):
      return .failure(failure)
    case .success(let minor):
      return .success(
        ManualTransactionDraft(
          date: now,
          amountMinor: minor,
          descriptionText: description,
          direction: isIncome ? .credit : .debit,
          categoryID: categoryID,
          accountID: nil))
    }
  }

  /// What Siri reads back. Deliberately states the direction as well as the
  /// amount: a mis-heard "income" is the one mistake here that is invisible
  /// afterwards on a screen the user did not open.
  public static func confirmation(for draft: ManualTransactionDraft) -> String {
    let verb = draft.direction == .credit ? "income" : "expense"
    return "Added \(verb) of ₹\(rupees(draft.amountMinor)) — \(draft.descriptionText)"
  }

  /// Paise back to a two-decimal string, by integer arithmetic.
  ///
  /// Two decimal places always: dividing into a `Decimal` and taking
  /// `stringValue` renders 24950 as "249.5", and Siri reads that out as "two
  /// hundred forty nine point five", which is not how anyone says an amount of
  /// money. Same idiom as `TransactionCSVExporter.plainDecimal`, kept local
  /// because that one is private to the exporter.
  private static func rupees(_ amountMinor: Int) -> String {
    let magnitude = abs(amountMinor)
    return "\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
  }
}
