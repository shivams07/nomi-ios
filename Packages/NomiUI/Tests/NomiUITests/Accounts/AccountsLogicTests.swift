import Foundation
import NomiCore
import NomiPreview
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

  /// The rename sheet prints "Tracked " before this, so the caption must not carry its own
  /// "tracked" (it once did, and the sheet read "Tracked tracked since"). The year stays.
  func testSinceCaptionDoesNotRepeatTrackedAndKeepsTheYear() {
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
    XCTAssertEqual(TrackedBalanceCaption.sinceText(date), "since 28 Sep 2026")
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

  /// R8. Grouping is read per locale: the comma is grouping in en_IN.
  func testGroupedNegativeParsesInLocale() {
    let locale = Locale(identifier: "en_IN")
    XCTAssertTrue(AccountOpeningBalanceField.isValid("-1,250.50", locale: locale))
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: "-1,250.50", locale: locale), -125_050)
  }

  func testGarbageIsInvalidInLocaleAndParsesToNil() {
    let locale = Locale(identifier: "en_IN")
    XCTAssertFalse(AccountOpeningBalanceField.isValid("abc", locale: locale))
    XCTAssertNil(AccountOpeningBalanceField.minorUnits(from: "abc", locale: locale))
  }

  /// R8. An opening balance may be zero or negative, down to -10^11 paise, and
  /// no further.
  func testOpeningBalanceBoundsMatchAmountRules() {
    let locale = Locale(identifier: "en_IN")
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: "-1000000000", locale: locale), -100_000_000_000)
    XCTAssertNil(AccountOpeningBalanceField.minorUnits(from: "-1000000000.01", locale: locale))
    XCTAssertFalse(AccountOpeningBalanceField.isValid("-1000000000.01", locale: locale))
    XCTAssertEqual(AccountOpeningBalanceField.minorUnits(from: "0", locale: locale), 0)
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

// MARK: - F1 / F2 follow-up (PR #123 review)

final class AccountDeleteRoutingTests: XCTestCase {
  /// "Archive instead" must reach the archive alert, never an archive made
  /// straight from the dialog. The alert is where the DEC-06 sentence shows.
  func testArchiveInsteadPresentsTheArchiveAlert() {
    XCTAssertEqual(AccountDeleteRouting.outcome(for: .archiveInstead), .presentArchiveAlert)
  }

  func testDeleteDeletes() {
    XCTAssertEqual(AccountDeleteRouting.outcome(for: .delete), .deleteAccount)
  }

  /// The alert the route leads to carries the DEC-06 disclosure.
  func testTheArchiveAlertCarriesTheDisclosure() {
    XCTAssertTrue(AccountBalanceDisplay.archiveMessage.contains(
      "Archived accounts are left out of your Estimated balance."
    ))
  }
}

final class AccountKindControlTests: XCTestCase {
  /// Each segment's tap target is at least the 44 pt minimum. The control was
  /// 40 pt per segment before this fix.
  func testEachSegmentIsAtLeastTheMinimumTapHeight() {
    XCTAssertGreaterThanOrEqual(AccountKindControl.segmentHeight, NomiSpacing.minTarget)
    XCTAssertEqual(NomiSpacing.minTarget, 44)
  }
}

// MARK: - S8: the card look, its text, the header, the note and the create path

final class NomiAccountCardStyleTests: XCTestCase {
  func testEachKindHasItsOwnLook() {
    XCTAssertEqual(NomiAccountCardStyle.of(kind: .bank), .moss)
    XCTAssertEqual(NomiAccountCardStyle.of(kind: .card), .black)
    XCTAssertEqual(NomiAccountCardStyle.of(kind: .wallet), .paper)
  }

  /// nomi.css `.pcard.moss` and `.pcard.black`, in the order the gradient runs.
  func testGradientStopsAreTheCanvasStops() {
    XCTAssertEqual(NomiAccountCardStyle.moss.gradientStops, [0x22392A, 0x3C5A38, 0x587C50])
    XCTAssertEqual(NomiAccountCardStyle.black.gradientStops, [0x232723, 0x0C0F0C, 0x1A1D1A])
  }

  /// Text on a moss or black card is white, so every stop must hold 4.5:1 against it.
  func testWhiteTextOnEveryMossAndBlackStopMeetsContrast() {
    for style in [NomiAccountCardStyle.moss, .black] {
      for stop in style.gradientStops {
        XCTAssertGreaterThanOrEqual(
          NomiContrast.ratio(0xFFFFFF, stop), 4.5,
          "white on \(String(stop, radix: 16)) in \(style)"
        )
      }
    }
  }

  /// The wallet is paper: no gradient, ink text.
  func testPaperHasNoGradientAndInkText() {
    XCTAssertTrue(NomiAccountCardStyle.paper.gradientStops.isEmpty)
    XCTAssertEqual(NomiAccountCardStyle.paper.foregroundHex, 0x111411)
    XCTAssertEqual(NomiAccountCardStyle.moss.foregroundHex, 0xFFFFFF)
  }
}

final class AccountCardTextTests: XCTestCase {
  func testTitleIsTheInstitutionWhenThereIsOne() {
    XCTAssertEqual(AccountCardText.title(institution: "HDFC Bank", displayName: "HDFC Savings"), "HDFC Bank")
  }

  func testTitleFallsBackToTheDisplayNameWithoutAnInstitution() {
    XCTAssertEqual(AccountCardText.title(institution: "", displayName: "Cash drawer"), "Cash drawer")
  }

  /// Different from the institution: the name gets the second line.
  func testSubtitleIsTheDisplayNameWhenItDiffersFromTheInstitution() {
    XCTAssertEqual(
      AccountCardText.subtitle(institution: "HDFC Bank", displayName: "HDFC Savings", kind: .bank),
      "HDFC Savings"
    )
  }

  /// Equal to the institution: the title already says it, so the kind label goes second.
  func testSubtitleIsTheKindLabelWhenTheNameEqualsTheInstitution() {
    XCTAssertEqual(
      AccountCardText.subtitle(institution: "HDFC Bank", displayName: "HDFC Bank", kind: .bank),
      "Bank account"
    )
  }

  /// No institution: the name is already the title, so the kind label goes second.
  func testSubtitleIsTheKindLabelWhenTheInstitutionIsEmpty() {
    XCTAssertEqual(
      AccountCardText.subtitle(institution: "", displayName: "Cash drawer", kind: .wallet),
      "Cash"
    )
  }

  func testKindLabelsMatchTheArtboardWords() {
    XCTAssertEqual(AccountCardText.kindLabel(.bank), "Bank account")
    XCTAssertEqual(AccountCardText.kindLabel(.card), "Credit card")
    XCTAssertEqual(AccountCardText.kindLabel(.wallet), "Cash")
  }

  func testLastFourIsMaskedAndAbsentWhenEmpty() {
    XCTAssertEqual(AccountCardText.lastFourLine("4471"), "•••• 4471")
    XCTAssertNil(AccountCardText.lastFourLine(""))
  }
}

final class AccountCardAccessibilityTests: XCTestCase {
  func testBankLabelNamesTheAccountEndingAndTheEstimatedBalance() {
    XCTAssertEqual(
      AccountCardAccessibility.label(displayName: "HDFC Savings", lastFour: "4471", kind: .bank, trackedMinor: 1_15_271_00),
      "HDFC Savings, account ending 4471, estimated balance 1,15,271 rupees"
    )
  }

  func testWalletLabelOmitsAnAccountEndingWhenThereIsNoLastFour() {
    XCTAssertEqual(
      AccountCardAccessibility.label(displayName: "Paytm wallet", lastFour: "", kind: .wallet, trackedMinor: 3_410_00),
      "Paytm wallet, estimated balance 3,410 rupees"
    )
  }

  /// A card below zero is owed, and the label says so rather than reading a minus.
  func testOwedCardLabelSpeaksTheAmountOwed() {
    XCTAssertEqual(
      AccountCardAccessibility.label(displayName: "ICICI Credit Card", lastFour: "9012", kind: .card, trackedMinor: -200_00),
      "ICICI Credit Card, account ending 9012, 200 rupees owed"
    )
  }

  func testPaiseAreSpokenWhenThereAreAny() {
    XCTAssertEqual(AccountCardAccessibility.spokenRupees(minor: 1_234_50), "1,234.50")
  }
}

final class AccountsHeaderTests: XCTestCase {
  func testHeaderWithoutATrackingDateIsJustTheLabel() {
    XCTAssertEqual(AccountsHeader.line(trackedSince: nil), "Estimated balance")
  }

  /// Any month works; October keeps the expected string free of a month name's locale quirks.
  func testHeaderNamesTheDayTrackingStarted() {
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    XCTAssertEqual(AccountsHeader.line(trackedSince: date), "Estimated balance · tracked since 1 Oct")
  }
}

final class UnassignedNoteTests: XCTestCase {
  func testNoNoteWhenEveryPaymentHasAnAccount() {
    XCTAssertNil(UnassignedNote.text(count: 0))
  }

  func testSingularNoteReadsForOnePayment() {
    XCTAssertEqual(
      UnassignedNote.text(count: 1),
      "1 payment has no account. Assign it so balances stay right."
    )
  }

  func testPluralNoteReadsForSeveralPayments() {
    XCTAssertEqual(
      UnassignedNote.text(count: 2),
      "2 payments have no account. Assign them so balances stay right."
    )
  }
}

@MainActor
final class AccountCreateActionTests: XCTestCase {
  private let indian = Locale(identifier: "en_IN")

  /// The opening balance is written in the same save as the account: one create, one row.
  func testAnOpeningBalanceIsWrittenWithTheAccountInOneCreate() throws {
    let store = FakeAccountStore(accounts: [])
    let account = try AccountCreateAction.perform(
      store: store,
      displayName: "  HDFC Savings ",
      institution: " HDFC Bank ",
      lastFour: "4471",
      kindRaw: "bank",
      openingBalanceText: "1200.50",
      locale: indian
    )
    XCTAssertEqual(store.accounts.count, 1)
    XCTAssertEqual(account.displayName, "HDFC Savings")
    XCTAssertEqual(account.institution, "HDFC Bank")
    XCTAssertEqual(account.openingBalanceMinor, 120_050)
  }

  func testAnEmptyOpeningBalanceCreatesWithNoBalance() throws {
    let store = FakeAccountStore(accounts: [])
    let account = try AccountCreateAction.perform(
      store: store, displayName: "Cash drawer", institution: "", lastFour: "",
      kindRaw: "wallet", openingBalanceText: "", locale: indian
    )
    XCTAssertNil(account.openingBalanceMinor)
  }

  /// An overdrawn card is entered as a negative amount, as the footer says.
  func testANegativeOpeningBalanceIsKeptForAnOwedCard() throws {
    let store = FakeAccountStore(accounts: [])
    let account = try AccountCreateAction.perform(
      store: store, displayName: "ICICI Credit Card", institution: "ICICI Bank", lastFour: "9012",
      kindRaw: "card", openingBalanceText: "-18420", locale: indian
    )
    XCTAssertEqual(account.openingBalanceMinor, -1_842_000)
  }
}
