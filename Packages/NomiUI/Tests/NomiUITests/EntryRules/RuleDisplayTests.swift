import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// S10: the Auto-categorise rows read as sentences, not glob patterns (canvas
/// `Rules`). The title strips one star from each end and title-cases the rest;
/// the scope line lists direction, account and amount in that order, in whole
/// rupees. `Account` is a `@Model`, so the account lookup is a closure over
/// plain strings here.
final class RuleDisplayTests: XCTestCase {
  private let accountID = UUID()

  private func accountLabel(_ id: UUID) -> String? {
    id == accountID ? "HDFC ••4471" : nil
  }

  // MARK: - Title

  func testTitleStripsBothStarsAndTitleCases() {
    XCTAssertEqual(RuleDisplay.title(pattern: "*BLUE TOKAI*"), "Blue Tokai")
  }

  func testMiddleStarLeavesThePatternUnchanged() {
    XCTAssertEqual(RuleDisplay.title(pattern: "*A*B*"), "*A*B*")
  }

  func testPatternWithoutStarsIsTitleCased() {
    XCTAssertEqual(RuleDisplay.title(pattern: "NETFLIX"), "Netflix")
  }

  func testLoneStarIsLeftAlone() {
    XCTAssertEqual(RuleDisplay.title(pattern: "*"), "*")
  }

  // MARK: - Scope line

  func testAnyScopeReadsAsAnyPayment() {
    XCTAssertEqual(RuleDisplay.scopeLine(.any, accountName: { _ in nil }), "Any payment")
  }

  func testDebitAloneReadsAsSpent() {
    XCTAssertEqual(RuleDisplay.scopeLine(RuleScope(direction: .debit), accountName: { _ in nil }), "Spent")
  }

  func testCreditAloneReadsAsIncome() {
    XCTAssertEqual(RuleDisplay.scopeLine(RuleScope(direction: .credit), accountName: { _ in nil }), "Income")
  }

  func testAccountAloneUsesTheLookedUpLabel() {
    XCTAssertEqual(RuleDisplay.scopeLine(RuleScope(accountID: accountID), accountName: accountLabel), "HDFC ••4471")
  }

  func testUnknownAccountFallsBack() {
    XCTAssertEqual(RuleDisplay.scopeLine(RuleScope(accountID: UUID()), accountName: accountLabel), "Unknown account")
  }

  func testBothBoundsReadAsARange() {
    let scope = RuleScope(minAmountMinor: 100_00, maxAmountMinor: 2000_00)
    XCTAssertEqual(RuleDisplay.scopeLine(scope, accountName: { _ in nil }), "₹100 to ₹2,000")
  }

  func testMinimumOnlyReadsAsOrMore() {
    let scope = RuleScope(minAmountMinor: 100_00)
    XCTAssertEqual(RuleDisplay.scopeLine(scope, accountName: { _ in nil }), "₹100 or more")
  }

  func testMaximumOnlyReadsAsUpTo() {
    let scope = RuleScope(maxAmountMinor: 2000_00)
    XCTAssertEqual(RuleDisplay.scopeLine(scope, accountName: { _ in nil }), "Up to ₹2,000")
  }

  func testPaiseAreDroppedFromTheAmount() {
    let scope = RuleScope(minAmountMinor: 100_50)
    XCTAssertEqual(RuleDisplay.scopeLine(scope, accountName: { _ in nil }), "₹100 or more")
  }

  func testAllThreePartsJoinInOrder() {
    let scope = RuleScope(
      direction: .debit,
      accountID: accountID,
      minAmountMinor: 100_00,
      maxAmountMinor: 2000_00
    )
    XCTAssertEqual(
      RuleDisplay.scopeLine(scope, accountName: accountLabel),
      "Spent · HDFC ••4471 · ₹100 to ₹2,000"
    )
  }

  // MARK: - Account label

  func testAccountLabelJoinsInstitutionAndMaskedLastFour() {
    XCTAssertEqual(RuleDisplay.accountLabel(institution: "HDFC", lastFour: "4471"), "HDFC ••4471")
  }

  func testAccountLabelWithoutLastFourIsTheInstitutionAlone() {
    XCTAssertEqual(RuleDisplay.accountLabel(institution: "HDFC", lastFour: ""), "HDFC")
  }

  func testAccountLabelWithoutInstitutionIsTheMaskedLastFour() {
    XCTAssertEqual(RuleDisplay.accountLabel(institution: "", lastFour: "4471"), "••4471")
  }

  // MARK: - Search

  func testEmptyQueryMatchesEveryRow() {
    XCTAssertTrue(RuleDisplay.matchesSearch("", title: "Netflix", categoryName: "Subscriptions"))
  }

  func testWhitespaceOnlyQueryMatchesEveryRow() {
    XCTAssertTrue(RuleDisplay.matchesSearch("   ", title: "Netflix", categoryName: "Subscriptions"))
  }

  func testQueryMatchesTheTitleIgnoringCase() {
    XCTAssertTrue(RuleDisplay.matchesSearch("netfl", title: "Netflix", categoryName: "Subscriptions"))
  }

  func testQueryMatchesTheCategoryName() {
    XCTAssertTrue(RuleDisplay.matchesSearch("SUBSCR", title: "Netflix", categoryName: "Subscriptions"))
  }

  func testQueryMatchingNeitherIsRejected() {
    XCTAssertFalse(RuleDisplay.matchesSearch("swiggy", title: "Netflix", categoryName: "Subscriptions"))
  }
}
