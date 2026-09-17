import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class RuleFormGateTests: XCTestCase {
  func testEmptyPatternIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "", categoryID: UUID(), scope: .any))
  }

  func testWhitespaceOnlyPatternIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "   ", categoryID: UUID(), scope: .any))
  }

  func testMissingCategoryIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: nil, scope: .any))
  }

  func testPatternAndCategoryIsValid() {
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: .any))
  }

  // MARK: - W2-M4: the "Only when" range

  func testEmptyScopeIsValid() {
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: .any))
  }

  func testMinGreaterThanMaxIsInvalid() {
    let scope = RuleScope(minAmountMinor: 2000_00, maxAmountMinor: 1000_00)
    XCTAssertFalse(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: scope))
  }

  func testMinEqualToMaxIsValid() {
    let scope = RuleScope(minAmountMinor: 1000_00, maxAmountMinor: 1000_00)
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: scope))
  }

  func testOnlyOneBoundSetIsValid() {
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: RuleScope(minAmountMinor: 1000_00)))
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID(), scope: RuleScope(maxAmountMinor: 1000_00)))
  }
}

final class RuleScopeAmountTests: XCTestCase {
  func testEmptyTextIsNoBound() {
    XCTAssertNil(RuleScopeAmount.bound(from: ""))
  }

  func testZeroTextIsNoBound() {
    XCTAssertNil(RuleScopeAmount.bound(from: "0"))
  }

  func testUnparseableTextIsNoBound() {
    XCTAssertNil(RuleScopeAmount.bound(from: "abc"))
  }

  func testValidTextIsMinorUnits() {
    XCTAssertEqual(RuleScopeAmount.bound(from: "10.50"), 1050)
  }
}

final class RuleScopeSummaryTests: XCTestCase {
  func testAnyScopeHasNoSummary() {
    XCTAssertNil(RuleScopeSummary.text(for: .any, accountName: { _ in nil }))
  }

  func testDirectionOnlySummary() {
    let scope = RuleScope(direction: .debit)
    XCTAssertEqual(RuleScopeSummary.text(for: scope, accountName: { _ in nil }), "Debit")
  }

  func testAccountNameSummary() {
    let accountID = UUID()
    let scope = RuleScope(accountID: accountID)
    let text = RuleScopeSummary.text(for: scope) { $0 == accountID ? "HDFC •• 4471" : nil }
    XCTAssertEqual(text, "HDFC •• 4471")
  }

  func testAmountRangeSummaryJoinsBothBounds() {
    let scope = RuleScope(minAmountMinor: 1000_00, maxAmountMinor: 2000_00)
    let text = RuleScopeSummary.text(for: scope, accountName: { _ in nil })
    XCTAssertTrue(text?.contains("–") ?? false)
  }

  func testMinOnlySummaryUsesAtLeast() {
    let scope = RuleScope(minAmountMinor: 1000_00)
    let text = RuleScopeSummary.text(for: scope, accountName: { _ in nil })
    XCTAssertTrue(text?.hasPrefix("≥") ?? false)
  }

  func testMultiplePartsAreJoined() {
    // Not an exact string match: `NomiFormatters.amountString`'s ICU
    // currency formatting inserts a space after "₹" on some runtimes (seen
    // on CI) and not others, and that spacing isn't this function's
    // contract to pin down — only that the two parts it owns joining
    // correctly with " · " is.
    let scope = RuleScope(direction: .credit, minAmountMinor: 500_00)
    let text = RuleScopeSummary.text(for: scope, accountName: { _ in nil }) ?? ""
    XCTAssertTrue(text.hasPrefix("Credit · ≥"))
    XCTAssertTrue(text.contains("500.00"))
  }
}
