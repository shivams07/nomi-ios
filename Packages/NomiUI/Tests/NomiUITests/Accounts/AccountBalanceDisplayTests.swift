import Foundation
import NomiCore
import Testing
@testable import NomiUI

// clt-harness: include

/// The money labels on the Accounts screen (AC, DEC-06). Vectors are from
/// A-06 in nomi-ios-decisions.md: bank 1,48,200.00, card -18,420.50 (tracked),
/// wallet 3,500.00 give a hero total of 1,33,279.50.
@Suite("Account balance display")
struct AccountBalanceDisplayTests {
  // MARK: - Row amount and "Owed"

  @Test func negativeCardIsOwedAtItsAbsoluteAmount() {
    #expect(AccountBalanceDisplay.line(kind: .card, trackedMinor: -18_420_50)
      == AccountBalanceDisplay.Line(minor: 18_420_50, caption: "Owed"))
  }

  @Test func positiveCardHasNoCaption() {
    #expect(AccountBalanceDisplay.line(kind: .card, trackedMinor: 500_00)
      == AccountBalanceDisplay.Line(minor: 500_00, caption: nil))
  }

  @Test func zeroCardHasNoCaption() {
    #expect(AccountBalanceDisplay.line(kind: .card, trackedMinor: 0)
      == AccountBalanceDisplay.Line(minor: 0, caption: nil))
  }

  @Test func negativeBankIsSignedWithNoCaption() {
    #expect(AccountBalanceDisplay.line(kind: .bank, trackedMinor: -200_00)
      == AccountBalanceDisplay.Line(minor: -200_00, caption: nil))
  }

  @Test func negativeWalletIsSignedWithNoCaption() {
    #expect(AccountBalanceDisplay.line(kind: .wallet, trackedMinor: -50_00)
      == AccountBalanceDisplay.Line(minor: -50_00, caption: nil))
  }

  // MARK: - Row caption precedence

  @Test func owedBeatsOpeningBalance() {
    #expect(AccountBalanceDisplay.rowCaption(kind: .card, trackedMinor: -18_420_50, openingMinor: 50_000_00) == "Owed")
  }

  @Test func openingCaptionShowsWhenSet() {
    #expect(AccountBalanceDisplay.rowCaption(kind: .bank, trackedMinor: 1_48_200_00, openingMinor: 1_20_000_00)
      == "Opening ₹1,20,000.00")
  }

  @Test func negativeOpeningKeepsItsSign() {
    #expect(AccountBalanceDisplay.rowCaption(kind: .card, trackedMinor: 500_00, openingMinor: -18_420_00)
      == "Opening \u{2212}₹18,420.00")
  }

  @Test func noCaptionWhenNeitherApplies() {
    #expect(AccountBalanceDisplay.rowCaption(kind: .bank, trackedMinor: 0, openingMinor: nil) == nil)
  }

  // MARK: - Hero total

  @Test func artboardVectorTotalIsOneLakhThirtyThreeThousandTwoHundredSeventyNineFiftyPaise() {
    let summaries: [(isArchived: Bool, trackedMinor: Int)] = [
      (isArchived: false, trackedMinor: 1_48_200_00),
      (isArchived: false, trackedMinor: -18_420_50),
      (isArchived: false, trackedMinor: 3_500_00),
    ]
    #expect(AccountBalanceDisplay.total(summaries) == 1_33_279_50)
  }

  @Test func totalExcludesArchivedAccounts() {
    let summaries: [(isArchived: Bool, trackedMinor: Int)] = [
      (isArchived: false, trackedMinor: 1_00_00),
      (isArchived: true, trackedMinor: 999_99),
    ]
    #expect(AccountBalanceDisplay.total(summaries) == 1_00_00)
  }

  @Test func totalOfOnlyArchivedAccountsIsZero() {
    let summaries: [(isArchived: Bool, trackedMinor: Int)] = [
      (isArchived: true, trackedMinor: 1_00_00),
      (isArchived: true, trackedMinor: -18_420_50),
    ]
    #expect(AccountBalanceDisplay.total(summaries) == 0)
  }

  @Test func totalOfNoAccountsIsZero() {
    let summaries: [(isArchived: Bool, trackedMinor: Int)] = []
    #expect(AccountBalanceDisplay.total(summaries) == 0)
  }

  @Test func archivingTheCardMovesTheTotalByExactlyItsTrackedBalance() {
    let active: [(isArchived: Bool, trackedMinor: Int)] = [
      (isArchived: false, trackedMinor: 1_48_200_00),
      (isArchived: false, trackedMinor: -18_420_50),
      (isArchived: false, trackedMinor: 3_500_00),
    ]
    let cardArchived: [(isArchived: Bool, trackedMinor: Int)] = [
      (isArchived: false, trackedMinor: 1_48_200_00),
      (isArchived: true, trackedMinor: -18_420_50),
      (isArchived: false, trackedMinor: 3_500_00),
    ]
    #expect(AccountBalanceDisplay.total(cardArchived) - AccountBalanceDisplay.total(active) == 18_420_50)
  }

  // MARK: - Footers and archive copy (DEC-06 strings)

  @Test func cardFooterSaysToEnterOwedAsNegative() {
    #expect(AccountBalanceDisplay.openingBalanceFooter(kind: .card)
      == "What this card held before Nomi started tracking it. If you owed money, enter it as a negative amount, for example -18420.00.")
  }

  @Test func bankFooterIsTheShippedSentence() {
    #expect(AccountBalanceDisplay.openingBalanceFooter(kind: .bank)
      == "What this account held before Nomi started tracking it. Leave blank if you don't know.")
  }

  @Test func walletFooterIsTheShippedSentence() {
    #expect(AccountBalanceDisplay.openingBalanceFooter(kind: .wallet)
      == AccountBalanceDisplay.openingBalanceFooter(kind: .bank))
  }

  @Test func archiveMessageCarriesTheTotalDisclosure() {
    #expect(AccountBalanceDisplay.archiveMessage.contains(
      "Archived accounts are left out of your Tracked balance. Their transactions stay in your history and totals."
    ))
  }

  @Test func archiveMessageKeepsTheExistingLine() {
    #expect(AccountBalanceDisplay.archiveMessage.hasPrefix(
      "Transactions are kept. You can unarchive this account anytime."
    ))
  }
}
