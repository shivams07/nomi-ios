import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S8 step 3. The model reads the summaries (archived included) and the unassigned
/// count, and owns the split, the total and the failed state. The spy records calls
/// so a test can see what was asked for.
@MainActor
final class AccountsModelTests: XCTestCase {
  private struct SpyFailure: Error {}

  private final class SpyInsightsStore: InsightsStore {
    var summaries: [AccountSummary] = []
    var unassigned: [NomiCore.Transaction] = []
    var failSummaries = false
    var failUnassigned = false
    private(set) var includeArchivedRequests: [Bool] = []

    func insights(for period: InsightPeriod) throws -> PeriodInsights { throw SpyFailure() }
    func trend(months: Int) throws -> [MonthBucket] { [] }
    func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] {
      includeArchivedRequests.append(includeArchived)
      if failSummaries { throw SpyFailure() }
      return summaries
    }
    func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
    func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
    func unassignedTransactions() throws -> [NomiCore.Transaction] {
      if failUnassigned { throw SpyFailure() }
      return unassigned
    }
  }

  private func summary(
    _ name: String,
    institution: String = "Bank",
    kindRaw: String = "bank",
    tracked: Int,
    since: Date? = nil,
    archived: Bool = false
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(),
      displayName: name,
      institution: institution,
      lastFour: "0000",
      kindRaw: kindRaw,
      trackedBalanceMinor: tracked,
      transactionCount: 0,
      trackingSince: since,
      isArchived: archived
    )
  }

  /// The artboard's three cards and the archived one.
  private func artboardSpy() -> SpyInsightsStore {
    let spy = SpyInsightsStore()
    spy.summaries = [
      summary("HDFC Savings", institution: "HDFC Bank", tracked: 1_15_271_00),
      summary("ICICI Credit Card", institution: "ICICI Bank", kindRaw: "card", tracked: -200_00),
      summary("Cash", institution: "", kindRaw: "wallet", tracked: 3_410_00),
      summary("Old Wallet", institution: "Paytm", kindRaw: "wallet", tracked: 900_00, archived: true),
    ]
    return spy
  }

  func testTheModelAsksForArchivedAccountsToo() {
    let spy = artboardSpy()
    AccountsModel(insightsStore: spy).load()
    XCTAssertEqual(spy.includeArchivedRequests, [true])
  }

  func testActiveAndArchivedAreSplit() {
    let model = AccountsModel(insightsStore: artboardSpy())
    model.load()
    XCTAssertEqual(model.state, .loaded)
    XCTAssertEqual(model.active.map(\.displayName), ["HDFC Savings", "ICICI Credit Card", "Cash"])
    XCTAssertEqual(model.archived.map(\.displayName), ["Old Wallet"])
  }

  /// The artboard total: 1,15,271 less 200 owed on the card, plus 3,410. The archived 900 is not in it.
  func testTotalIsTheSumOfTheActiveBalancesWithTheOwedCardNegative() {
    let model = AccountsModel(insightsStore: artboardSpy())
    model.load()
    XCTAssertEqual(model.totalMinor, 1_18_481_00)
  }

  func testUnassignedCountIsTheNumberOfUnassignedRows() {
    let spy = artboardSpy()
    spy.unassigned = [
      NomiCore.Transaction(date: Date(), amountMinor: 450_00, directionRaw: Direction.debit.rawValue),
      NomiCore.Transaction(date: Date(), amountMinor: 120_00, directionRaw: Direction.debit.rawValue),
    ]
    let model = AccountsModel(insightsStore: spy)
    model.load()
    XCTAssertEqual(model.unassignedCount, 2)
  }

  /// Tracking starts at the earliest active account. An archived account that started earlier does not move it.
  func testTrackingSinceIsTheEarliestActiveAccount() {
    let early = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
    let later = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15))!
    let archivedEarlier = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!
    let spy = SpyInsightsStore()
    spy.summaries = [
      summary("Savings", tracked: 1_00, since: later),
      summary("Current", tracked: 2_00, since: early),
      summary("Old", tracked: 3_00, since: archivedEarlier, archived: true),
    ]
    let model = AccountsModel(insightsStore: spy)
    model.load()
    XCTAssertEqual(model.trackingSince, early)
  }

  /// A failed read is `.failed`, not an empty screen, and shows no total.
  func testAFailedSummaryReadIsFailedNotEmpty() {
    let spy = artboardSpy()
    spy.failSummaries = true
    let model = AccountsModel(insightsStore: spy)
    model.load()
    XCTAssertEqual(model.state, .failed)
    XCTAssertTrue(model.active.isEmpty)
    XCTAssertTrue(model.archived.isEmpty)
    XCTAssertEqual(model.totalMinor, 0)
  }

  func testAFailedUnassignedReadIsFailedToo() {
    let spy = artboardSpy()
    spy.failUnassigned = true
    let model = AccountsModel(insightsStore: spy)
    model.load()
    XCTAssertEqual(model.state, .failed)
    XCTAssertTrue(model.active.isEmpty)
  }

  func testAnEmptyLedgerIsLoadedAndEmpty() {
    let model = AccountsModel(insightsStore: SpyInsightsStore())
    model.load()
    XCTAssertEqual(model.state, .loaded)
    XCTAssertTrue(model.active.isEmpty)
    XCTAssertTrue(model.archived.isEmpty)
    XCTAssertNil(model.trackingSince)
    XCTAssertEqual(model.unassignedCount, 0)
  }
}
