import Foundation
import XCTest

@testable import NomiUI

/// M3. `AccountArchivable` exists precisely so this is testable without
/// constructing a real `NomiCore.Account` (`@Model`) — same
/// `StubRow`-over-a-protocol pattern `LedgerLogicTests`/`RecentTransactionsTests`
/// already use for their own `@Model` types.
private struct StubAccount: AccountArchivable {
  let id: UUID
  let isArchived: Bool
}

final class EntryAccountTests: XCTestCase {

  func testExactlyOneActiveAccountIsPreselected() {
    let account = StubAccount(id: UUID(), isArchived: false)

    XCTAssertEqual(EntryAccountDefault.preselection(from: [account]), account.id)
  }

  func testZeroAccountsPreselectsNothing() {
    XCTAssertNil(EntryAccountDefault.preselection(from: [StubAccount]()))
  }

  func testTwoActiveAccountsPreselectsNothing() {
    let accounts = [
      StubAccount(id: UUID(), isArchived: false),
      StubAccount(id: UUID(), isArchived: false),
    ]

    XCTAssertNil(EntryAccountDefault.preselection(from: accounts))
  }

  /// The rule counts *active* accounts, not accounts — an archived one sits
  /// in the array but must not turn an otherwise-unambiguous single active
  /// account into an ambiguous two.
  func testAnArchivedAccountAlongsideOneActiveOneIsStillPreselected() {
    let active = StubAccount(id: UUID(), isArchived: false)
    let archived = StubAccount(id: UUID(), isArchived: true)

    XCTAssertEqual(EntryAccountDefault.preselection(from: [active, archived]), active.id)
  }

  /// The mirror of the test above: two *active* accounts plus an archived
  /// one is still ambiguous — the archived row must not be what saves it
  /// from `nil`.
  func testTwoActiveAccountsPlusAnArchivedOneIsStillAmbiguous() {
    let accounts = [
      StubAccount(id: UUID(), isArchived: false),
      StubAccount(id: UUID(), isArchived: false),
      StubAccount(id: UUID(), isArchived: true),
    ]

    XCTAssertNil(EntryAccountDefault.preselection(from: accounts))
  }

  /// `EntrySaveGate`'s signature must never grow an `accountID` parameter —
  /// the chip is prefilled and optional, and gating Save on it would quietly
  /// trade away the two-tap done-when. Asserting the call compiles with only
  /// `amountMinor:` is what would break if a label were added.
  func testEntrySaveGateSignatureTakesOnlyAmountMinor() {
    XCTAssertTrue(EntrySaveGate.isEnabled(amountMinor: 100))
  }

  // MARK: - Last used first (Andrews ruling, S5)

  /// The last account the user chose opens the next entry, when it is still
  /// active, even with several accounts to choose from.
  func testLastUsedWinsWhenItIsActive() {
    let first = StubAccount(id: UUID(), isArchived: false)
    let second = StubAccount(id: UUID(), isArchived: false)

    XCTAssertEqual(EntryAccountDefault.initial(lastUsed: second.id, from: [first, second]), second.id)
  }

  /// With no last-used account, the rule for one active account still applies.
  func testNilLastUsedFallsBackToTheSingleActiveAccount() {
    let only = StubAccount(id: UUID(), isArchived: false)

    XCTAssertEqual(EntryAccountDefault.initial(lastUsed: nil, from: [only]), only.id)
  }

  /// With no last-used account and two active ones, nothing is guessed.
  func testNilLastUsedWithTwoActiveAccountsPreselectsNothing() {
    let accounts = [
      StubAccount(id: UUID(), isArchived: false),
      StubAccount(id: UUID(), isArchived: false),
    ]

    XCTAssertNil(EntryAccountDefault.initial(lastUsed: nil, from: accounts))
  }

  /// An archived last-used account is not offered, so it cannot be the default.
  func testArchivedLastUsedFallsBackToTheRule() {
    let active = StubAccount(id: UUID(), isArchived: false)
    let archived = StubAccount(id: UUID(), isArchived: true)

    XCTAssertEqual(EntryAccountDefault.initial(lastUsed: archived.id, from: [active, archived]), active.id)
  }

  /// A last-used id that matches no account at all (the account was deleted)
  /// falls back in the same way.
  func testUnknownLastUsedFallsBackToTheRule() {
    let only = StubAccount(id: UUID(), isArchived: false)

    XCTAssertEqual(EntryAccountDefault.initial(lastUsed: UUID(), from: [only]), only.id)
  }
}
