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
}
