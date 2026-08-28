import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class AccountRenameGateTests: XCTestCase {
  func testEmptyNameIsInvalid() {
    XCTAssertFalse(AccountRenameGate.isValid(name: ""))
  }

  func testWhitespaceOnlyNameIsInvalid() {
    XCTAssertFalse(AccountRenameGate.isValid(name: "   "))
  }

  func testNonEmptyNameIsValid() {
    XCTAssertTrue(AccountRenameGate.isValid(name: "Checking"))
  }
}

final class TrackedBalanceTextTests: XCTestCase {
  func testPositiveBalanceHasNoSign() {
    let text = TrackedBalanceText.string(minor: 128_450_00)
    XCTAssertFalse(text.hasPrefix("-"))
    XCTAssertTrue(text.contains("₹"))
  }

  func testNegativeBalanceIsPrefixedWithMinus() {
    let text = TrackedBalanceText.string(minor: -4_200_00)
    XCTAssertTrue(text.hasPrefix("-₹"))
  }

  func testZeroBalanceHasNoSign() {
    let text = TrackedBalanceText.string(minor: 0)
    XCTAssertFalse(text.hasPrefix("-"))
  }
}

final class TrackedBalanceCaptionTests: XCTestCase {
  func testNilTrackingSinceProducesNoCaption() {
    XCTAssertNil(TrackedBalanceCaption.sinceText(nil))
  }

  func testTrackingSinceProducesSinceCaption() {
    let caption = TrackedBalanceCaption.sinceText(Date())
    XCTAssertNotNil(caption)
    XCTAssertTrue(caption!.hasPrefix("since "))
  }
}

final class AccountSectioningTests: XCTestCase {
  private func summary(isArchived: Bool) -> AccountSummary {
    AccountSummary(
      id: UUID(),
      displayName: "Account",
      institution: "Bank",
      lastFour: "0000",
      kindRaw: "bank",
      trackedBalanceMinor: 0,
      transactionCount: 0,
      trackingSince: nil,
      isArchived: isArchived
    )
  }

  func testActiveExcludesArchived() {
    let summaries = [summary(isArchived: false), summary(isArchived: true)]
    XCTAssertEqual(AccountSectioning.active(summaries).count, 1)
    XCTAssertFalse(AccountSectioning.active(summaries)[0].isArchived)
  }

  func testArchivedExcludesActive() {
    let summaries = [summary(isArchived: false), summary(isArchived: true)]
    XCTAssertEqual(AccountSectioning.archived(summaries).count, 1)
    XCTAssertTrue(AccountSectioning.archived(summaries)[0].isArchived)
  }
}
