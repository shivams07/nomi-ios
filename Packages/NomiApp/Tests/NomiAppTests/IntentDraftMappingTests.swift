import Foundation
import NomiCore
import XCTest

@testable import NomiApp

/// U23. Everything the intent decides lives in `IntentDraftMapping`, because
/// an `AppIntent` needs the intents runtime and a host app and so cannot be
/// exercised by `swift test` at all. These tests are the only automated
/// coverage this unit has; the Shortcuts half is verifiable on a device only.
final class IntentDraftMappingTests: XCTestCase {

  // MARK: - Amount

  /// The headline case. `12.99` is not representable in binary floating point,
  /// so `Int(12.99 * 100)` through a `Double` is 1298 — one paisa lost per
  /// entry, silently. This is the test that catches a future refactor to
  /// `Double`.
  func testTwoDecimalPlacesConvertExactlyToPaise() throws {
    let amount = try XCTUnwrap(Decimal(string: "12.99"))

    XCTAssertEqual(IntentDraftMapping.minorUnits(from: amount), .success(1299))
  }

  func testWholeRupeesConvert() throws {
    let amount = try XCTUnwrap(Decimal(string: "250"))

    XCTAssertEqual(IntentDraftMapping.minorUnits(from: amount), .success(25000))
  }

  /// Rejected rather than rounded. A third decimal place is a typo or a
  /// currency this app does not handle; guessing which is worse than declining,
  /// and a rounded amount stops the ledger reconciling with the bank.
  func testMoreThanTwoDecimalPlacesIsRejected() throws {
    let amount = try XCTUnwrap(Decimal(string: "12.999"))

    XCTAssertEqual(IntentDraftMapping.minorUnits(from: amount), .failure(.tooPrecise))
  }

  func testZeroAndNegativeAmountsAreRejected() throws {
    XCTAssertEqual(IntentDraftMapping.minorUnits(from: Decimal.zero), .failure(.outOfRange))
    XCTAssertEqual(
      IntentDraftMapping.minorUnits(from: try XCTUnwrap(Decimal(string: "-5"))),
      .failure(.outOfRange))
  }

  /// Siri mis-hearing a long number must not overflow into a negative row.
  func testAnAmountLargerThanTheAppCanRepresentIsRejected() throws {
    let amount = try XCTUnwrap(Decimal(string: "999999999999999999999"))

    XCTAssertEqual(IntentDraftMapping.minorUnits(from: amount), .failure(.outOfRange))
  }

  // MARK: - Parsing what Shortcuts collected

  /// R8b. The amount arrives as text and is parsed by `AmountText.parse` in en_IN.
  /// Fixture table for the review: every row the spec names.
  func testTheTextParserTable() {
    let rows: [(text: String, expected: Result<Int, IntentDraftMapping.Failure>)] = [
      ("12.99", .success(1299)),
      ("1,234.50", .success(123_450)),
      ("₹499", .success(49_900)),
      ("INR 499", .success(49_900)),
      ("Rs. 499", .success(49_900)),
      ("Rs 499", .success(49_900)),
      ("  499  ", .success(49_900)),
      ("₹ 1,00,000", .success(10_000_000)),
      ("", .failure(.notANumber)),
      ("   ", .failure(.notANumber)),
      ("abc", .failure(.notANumber)),
      ("₹", .failure(.notANumber)),
      ("2k", .failure(.notANumber)),
      ("12.999", .failure(.tooPrecise)),
      ("0", .failure(.outOfRange)),
      ("-5", .failure(.outOfRange)),
      ("1000000000", .success(100_000_000_000)),
      ("1000000000.01", .failure(.outOfRange)),
      ("999999999999999999999", .failure(.outOfRange)),
    ]
    let en = Locale(identifier: "en_IN")
    for row in rows {
      XCTAssertEqual(
        IntentDraftMapping.minorUnits(fromText: row.text, locale: en), row.expected,
        "failed for \(row.text)")
    }
  }

  /// `Decimal(string:)` stops at the first comma, so an unstripped "1,234.50"
  /// parses as 1 - a hundred-fold error on an amount the user typed correctly.
  func testGroupSeparatorsDoNotTruncateTheAmount() throws {
    XCTAssertEqual(
      IntentDraftMapping.minorUnits(fromText: "1,234.50", locale: Locale(identifier: "en_IN")),
      .success(123_450), "not 100")

    let made = try draftText("1,234.50").get()
    XCTAssertEqual(made.amountMinor, 123450, "not 100")
  }

  /// The amount is checked before the description, so a bad amount with a blank
  /// description reports the amount.
  func testAmountIsCheckedBeforeDescription() {
    let result = IntentDraftMapping.draft(
      amountText: "2k", note: nil, categoryID: nil, isIncome: false,
      locale: Locale(identifier: "en_IN"))
    XCTAssertEqual(failure(result), .notANumber)
  }

  /// The Decimal path keeps its precision rule and its upper bound is now the
  /// app's maximum, not Int.max.
  func testTheDecimalOverloadCapsAtTheMaximum() throws {
    XCTAssertEqual(
      IntentDraftMapping.minorUnits(from: try XCTUnwrap(Decimal(string: "1000000000.01"))),
      .failure(.outOfRange))
    XCTAssertEqual(
      IntentDraftMapping.minorUnits(from: try XCTUnwrap(Decimal(string: "1000000000"))),
      .success(100_000_000_000))
  }

  /// The copy the user hears for an amount the store refuses. R8b step 7.
  func testOutOfRangeCopyIsExact() {
    XCTAssertEqual(
      String(localized: AddTransactionError.outOfRange.localizedStringResource),
      "Amounts must be from ₹0.01 to ₹1,00,00,00,000.")
    guard case .outOfRange = AddTransactionError(.outOfRange) else {
      return XCTFail("IntentDraftMapping.Failure.outOfRange must map to AddTransactionError.outOfRange")
    }
  }

  /// The precision rule still applies to text that parsed fine.
  func testAPreciseTypedAmountIsStillRejected() {
    XCTAssertEqual(failure(draftText("12.999")), .tooPrecise)
  }

  // MARK: - Draft

  /// `isIncome` flips the direction rather than accepting a negative amount:
  /// "add minus five hundred" is not a sentence anyone says to Siri.
  func testIsIncomeFlipsTheDirection() throws {
    let expense = try draft(amount: "500", isIncome: false).get()
    let income = try draft(amount: "500", isIncome: true).get()

    XCTAssertEqual(expense.direction, .debit)
    XCTAssertEqual(income.direction, .credit)
    XCTAssertEqual(expense.amountMinor, 50000)
    XCTAssertEqual(income.amountMinor, 50000, "the amount is unsigned either way")
  }

  /// Stored verbatim, as a bank narration is. The pipeline derives
  /// `normalizedDescription` and `dedupeKey` from it like any other row.
  func testTheDescriptionIsTrimmedButOtherwiseKeptAsDictated() throws {
    let made = try draft(amount: "99", note: "  Flat white at Blue Tokai  ").get()

    XCTAssertEqual(made.descriptionText, "Flat white at Blue Tokai")
  }

  func testABlankOrWhitespaceOnlyDescriptionIsRejected() {
    XCTAssertEqual(failure(draft(amount: "99", note: nil)), .blankDescription)
    XCTAssertEqual(failure(draft(amount: "99", note: "   ")), .blankDescription)
  }

  /// The amount is checked even when the description is fine, and the
  /// description even when the amount is fine — neither guard shadows the other.
  func testAPreciseAmountIsRejectedEvenWithAGoodDescription() {
    XCTAssertEqual(failure(draft(amount: "12.999", note: "Coffee")), .tooPrecise)
  }

  /// R8b, ruling 4. When the amount and the description both fail, the amount error is
  /// reported. The Decimal overload used to report a blank description first.
  func testTheAmountErrorIsReportedWhenTheDescriptionIsAlsoBlank() throws {
    let precise = try XCTUnwrap(Decimal(string: "12.999"))
    XCTAssertEqual(
      failure(IntentDraftMapping.draft(amount: precise, note: "   ", categoryID: nil, isIncome: false)),
      .tooPrecise)
    XCTAssertEqual(
      failure(IntentDraftMapping.draft(amount: precise, note: nil, categoryID: nil, isIncome: false)),
      .tooPrecise)
    let zero = try XCTUnwrap(Decimal(string: "0"))
    XCTAssertEqual(
      failure(IntentDraftMapping.draft(amount: zero, note: nil, categoryID: nil, isIncome: false)),
      .outOfRange)
  }

  func testTheCategoryIsCarriedThroughAndIsOptional() throws {
    let id = UUID()

    XCTAssertEqual(try draft(amount: "99", categoryID: id).get().categoryID, id)
    XCTAssertNil(try draft(amount: "99").get().categoryID)
  }

  /// No account is assigned. The intent has no way to ask for one, and
  /// inventing a default would bind rows to an account the user never chose.
  func testNoAccountIsAssigned() throws {
    XCTAssertNil(try draft(amount: "99").get().accountID)
  }

  // MARK: - Spoken confirmation

  /// Siri reads the direction back as well as the amount. A mis-heard "income"
  /// is the one mistake here that is invisible afterwards on a screen the user
  /// did not open.
  func testTheConfirmationStatesTheDirectionAndTheAmount() throws {
    let expense = try draft(amount: "249.50", note: "Groceries").get()
    let income = try draft(amount: "249.50", note: "Refund", isIncome: true).get()

    XCTAssertEqual(
      IntentDraftMapping.confirmation(for: expense), "Added expense of ₹249.50 — Groceries")
    XCTAssertEqual(
      IntentDraftMapping.confirmation(for: income), "Added income of ₹249.50 — Refund")
  }

  /// Whole rupees still read with both decimal places - "249" would be spoken
  /// as an integer and sounds like a different kind of number.
  func testTheConfirmationAlwaysUsesTwoDecimalPlaces() throws {
    let whole = try draft(amount: "500", note: "Rent").get()

    XCTAssertEqual(IntentDraftMapping.confirmation(for: whole), "Added expense of ₹500.00 — Rent")
  }

  // MARK: -

  /// `ManualTransactionDraft` is not `Equatable`, so a `Result` wrapping one
  /// cannot be compared directly.
  private func failure(
    _ result: Result<ManualTransactionDraft, IntentDraftMapping.Failure>
  ) -> IntentDraftMapping.Failure? {
    guard case .failure(let failure) = result else { return nil }
    return failure
  }

  private func draftText(_ amountText: String) -> Result<
    ManualTransactionDraft, IntentDraftMapping.Failure
  > {
    IntentDraftMapping.draft(
      amountText: amountText, note: "Coffee", categoryID: nil, isIncome: false,
      locale: Locale(identifier: "en_IN"))
  }

  private func draft(
    amount: String,
    note: String? = "Coffee",
    categoryID: UUID? = nil,
    isIncome: Bool = false
  ) -> Result<ManualTransactionDraft, IntentDraftMapping.Failure> {
    IntentDraftMapping.draft(
      amount: Decimal(string: amount)!,
      note: note,
      categoryID: categoryID,
      isIncome: isIncome)
  }
}
