import Foundation
import NomiCore
import XCTest
@testable import NomiUI

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

final class AccountCreateFormGateTests: XCTestCase {
  func testBlankNameIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "", lastFour: "4471"))
  }

  func testWhitespaceOnlyNameIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "   ", lastFour: "4471"))
  }

  func testThreeDigitLastFourIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: "471"))
  }

  func testFiveDigitLastFourIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: "44712"))
  }

  func testMaskedLastFourIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: "•• 4471"))
  }

  func testNonDigitLastFourIsInvalid() {
    XCTAssertFalse(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: "abcd"))
  }

  func testEmptyLastFourIsValid() {
    XCTAssertTrue(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: ""))
  }

  func testFourDigitLastFourIsValid() {
    XCTAssertTrue(AccountCreateFormGate.isValid(displayName: "Checking", lastFour: "4471"))
  }
}

final class AccountOpeningBalanceFieldTests: XCTestCase {
  func testNilMinorProducesEmptyString() {
    XCTAssertEqual(AccountOpeningBalanceField.string(minor: nil), "")
  }

  func testPositiveMinorRoundTrips() {
    let text = AccountOpeningBalanceField.string(minor: 128_450_00)
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: text), 128_450_00)
  }

  func testZeroMinorRoundTripsAsExplicitZero() {
    let text = AccountOpeningBalanceField.string(minor: 0)
    XCTAssertNotEqual(text, "")
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: text), 0)
  }

  func testNegativeMinorRoundTrips() {
    let text = AccountOpeningBalanceField.string(minor: -4_200_00)
    XCTAssertTrue(text.hasPrefix("-"))
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: text), -4_200_00)
  }

  func testEmptyTextIsValidAndMeansClear() {
    XCTAssertTrue(AccountOpeningBalanceField.isValid(""))
    XCTAssertNil(AccountOpeningBalanceField.minorUnits(from: ""))
  }

  func testExplicitZeroTextIsValidAndDistinctFromClear() {
    XCTAssertTrue(AccountOpeningBalanceField.isValid("0"))
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: "0"), 0)
  }

  func testNegativeTextIsValid() {
    XCTAssertTrue(AccountOpeningBalanceField.isValid("-500.50"))
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: "-500.50"), -50_050)
  }

  func testMoreThanTwoDecimalDigitsIsInvalid() {
    XCTAssertFalse(AccountOpeningBalanceField.isValid("100.999"))
  }

  func testTwoDecimalDigitsIsValid() {
    XCTAssertTrue(AccountOpeningBalanceField.isValid("100.99"))
  }

  func testBareMinusSignIsInvalid() {
    XCTAssertFalse(AccountOpeningBalanceField.isValid("-"))
  }

  func testNonNumericTextIsInvalid() {
    XCTAssertFalse(AccountOpeningBalanceField.isValid("abc"))
  }
}

final class AccountEditFormGateTests: XCTestCase {
  func testBlankNameIsInvalid() {
    XCTAssertFalse(AccountEditFormGate.isValid(displayName: "", lastFour: "4471", openingBalanceText: ""))
  }

  func testMalformedLastFourIsInvalid() {
    XCTAssertFalse(AccountEditFormGate.isValid(displayName: "Checking", lastFour: "471", openingBalanceText: ""))
  }

  func testMalformedOpeningBalanceIsInvalid() {
    XCTAssertFalse(AccountEditFormGate.isValid(displayName: "Checking", lastFour: "4471", openingBalanceText: "not a number"))
  }

  func testAllValidFieldsAreValid() {
    XCTAssertTrue(AccountEditFormGate.isValid(displayName: "Checking", lastFour: "4471", openingBalanceText: "15000.00"))
  }

  func testEmptyOpeningBalanceIsValid() {
    XCTAssertTrue(AccountEditFormGate.isValid(displayName: "Checking", lastFour: "", openingBalanceText: ""))
  }
}

final class AccountDeleteConfirmationTests: XCTestCase {
  func testZeroTransactionsMessageHasNoCount() {
    let message = AccountDeleteConfirmation.message(transactionCount: 0)
    XCTAssertTrue(message.contains("no transactions"))
    XCTAssertTrue(message.contains("can't be undone"))
  }

  func testOneTransactionMessageIsSingular() {
    let message = AccountDeleteConfirmation.message(transactionCount: 1)
    XCTAssertTrue(message.contains("Its 1 transaction "))
    XCTAssertFalse(message.contains("1 transactions"))
  }

  func testManyTransactionsMessageIsPlural() {
    let message = AccountDeleteConfirmation.message(transactionCount: 42)
    XCTAssertTrue(message.contains("Its 42 transactions "))
  }

  func testMessageNamesTransactionsAsKeptNotDeleted() {
    let message = AccountDeleteConfirmation.message(transactionCount: 5)
    XCTAssertTrue(message.contains("kept"))
    XCTAssertFalse(message.localizedCaseInsensitiveContains("delete the transactions"))
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

  // MARK: - U15: the picker's choices come from the model

  /// A hand-written list here is a list that silently disagrees with what the
  /// store will accept — which surfaces as a picker offering a kind that
  /// throws on Save.
  func testTheKindOptionsAreDerivedFromAccountKind() {
    XCTAssertEqual(AccountKindOptions.all, AccountKind.allCases.map(\.rawValue))
    XCTAssertEqual(AccountKindOptions.all, ["bank", "card", "wallet"])
    XCTAssertEqual(AccountKindOptions.defaultKind, AccountKind.bank.rawValue)
    XCTAssertTrue(AccountKindOptions.all.contains(AccountKindOptions.defaultKind))
  }

  /// Every option the picker can offer is one the store accepts. This is the
  /// assertion that would have caught the two lists drifting.
  func testEveryOfferedKindIsARecognisedAccountKind() {
    for option in AccountKindOptions.all {
      XCTAssertNotNil(AccountKind(rawValue: option), option)
    }
  }
}
