import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// Exercises `RecentRows.mostRecent` against a plain stub, never a real
/// `Transaction`. Not because one cannot be built: a container constructs fine
/// under XCTest and only swift-testing traps (see `InMemoryModelContainer`'s
/// measured note in NomiCore). `DatedRow` exists so this algorithm can be
/// verified with no container, no schema and no store — which is a better test
/// of a sort than one needing all three.
private struct StubRow: DatedRow, Equatable {
  let label: String
  let date: Date
}

final class RecentTransactionsSortTests: XCTestCase {
  private func day(_ offset: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(offset * 86_400))
  }

  func testOrdersNewestFirst() {
    let rows = [
      StubRow(label: "old", date: day(1)),
      StubRow(label: "newest", date: day(3)),
      StubRow(label: "middle", date: day(2)),
    ]
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.map(\.label), ["newest", "middle", "old"])
  }

  func testLimitsToRequestedCount() {
    let rows = (0..<20).map { StubRow(label: "row-\($0)", date: day($0)) }
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.count, 5)
    XCTAssertEqual(result.first?.label, "row-19")
  }

  func testFewerRowsThanLimitReturnsAllOfThem() {
    let rows = (0..<3).map { StubRow(label: "row-\($0)", date: day($0)) }
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.count, 3)
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertTrue(RecentRows.mostRecent([StubRow](), limit: 5).isEmpty)
  }
}

/// HM2. The Recent row's text and signed figure (DEC-03, A-03). Lives in this
/// file because the plan's HM2 file list has no separate row test file.
final class RecentRowTextTests: XCTestCase {

  func testTitleFallsBackFromMerchantToDescriptionToCategoryToManualEntry() {
    XCTAssertEqual(RecentRowText.title(merchantName: "Swiggy", descriptionText: "UPI/x", categoryName: "Food"), "Swiggy")
    XCTAssertEqual(RecentRowText.title(merchantName: "", descriptionText: "UPI/x", categoryName: "Food"), "UPI/x")
    XCTAssertEqual(RecentRowText.title(merchantName: nil, descriptionText: "  \n", categoryName: "Food"), "Food")
    XCTAssertEqual(RecentRowText.title(merchantName: nil, descriptionText: "", categoryName: nil), "Manual entry")
  }

  func testSubtitleIsTheCategoryOrUncategorized() {
    XCTAssertEqual(RecentRowText.subtitle(categoryName: "Food & Dining"), "Food & Dining")
    XCTAssertEqual(RecentRowText.subtitle(categoryName: nil), "Uncategorized")
  }

  /// Mutation target: flipping this sign drops the "−" from every debit row.
  func testDebitSignedMinorIsNegativeSoTheMinusPrints() {
    let signed = RecentRowText.signedMinor(amountMinor: 64_800, direction: .debit)
    XCTAssertEqual(signed, -64_800)
    XCTAssertEqual(NomiAmountFormat.parts(minor: signed).sign, "\u{2212}")
  }

  func testCreditSignedMinorStaysPositiveAndTakesThePlus() {
    let signed = RecentRowText.signedMinor(amountMinor: 3_850_000, direction: .credit)
    XCTAssertEqual(signed, 3_850_000)
    XCTAssertEqual(NomiAmountFormat.parts(minor: signed, showPlus: true).sign, "+")
  }

  /// A stored negative magnitude must not flip a credit or double-negate a debit.
  func testSignComesFromDirectionNotFromAStoredNegative() {
    XCTAssertEqual(RecentRowText.signedMinor(amountMinor: -64_800, direction: .debit), -64_800)
    XCTAssertEqual(RecentRowText.signedMinor(amountMinor: -3_850_000, direction: .credit), 3_850_000)
  }

  func testZeroCarriesNoSign() {
    XCTAssertEqual(NomiAmountFormat.parts(minor: RecentRowText.signedMinor(amountMinor: 0, direction: .debit)).sign, "")
    XCTAssertEqual(NomiAmountFormat.parts(minor: 0, showPlus: true).sign, "")
  }

  func testAccessibilityLabelNamesTheDirectionWord() {
    let debit = RecentRowText.accessibilityLabel(
      title: "Swiggy", direction: .debit, amountMinor: 64_800, currencyCode: "INR", categoryName: "Food & Dining"
    )
    let credit = RecentRowText.accessibilityLabel(
      title: "Acme Payroll", direction: .credit, amountMinor: 3_850_000, currencyCode: "INR", categoryName: nil
    )
    XCTAssertEqual(debit, "Swiggy, debit ₹648.00, Food & Dining")
    XCTAssertEqual(credit, "Acme Payroll, credit ₹38,500.00, Uncategorized")
  }
}
