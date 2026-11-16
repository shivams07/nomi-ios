import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `SettingsModel` (T2a, S9a). The store-recovery notice, the Accounts row's
/// reads and the "Export everything" file. Nothing here sleeps or awaits a task.
@MainActor
final class SettingsModelTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!

  private struct SpyFailure: Error {}

  override func setUp() {
    super.setUp()
    suiteName = "T2.Settings.\(UUID())"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults?.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  private func notice() -> StoreRecoveryNotice {
    StoreRecoveryNotice(movedAt: Date(timeIntervalSince1970: 1_794_648_612), fileName: "default-20261114T093012.store")
  }

  /// Dismiss forgets the record in the suite and hides the row. Kills T2-M14.
  func testDismissClearsTheRecordAndHidesTheRow() throws {
    StoreRecoveryRecord.save(notice(), to: defaults)
    let model = SettingsModel(storeRecovery: notice(), recoveryDefaults: defaults)
    XCTAssertNotNil(model.storeRecovery)

    model.dismissStoreRecovery()

    XCTAssertNil(StoreRecoveryRecord.load(from: defaults))
    XCTAssertNil(model.storeRecovery)
  }

  /// The recovery row has no chevron, and says what the notice says. Kills T2-M15.
  func testRecoveryRowHasNoChevron() {
    let row = SettingsScreen.storeRecoveryRow(notice())

    XCTAssertFalse(row.showsChevron)
    XCTAssertEqual(row.title, "Saved data couldn’t be opened")
    XCTAssertEqual(row.message, StoreRecoveryDisplay.caption(for: notice()))
  }

  // MARK: - S9a step 2: the Accounts row reads what Accounts reads

  /// Archived accounts are left out of the count and the total, as on the Accounts
  /// screen. The total is signed, so an owed card takes away from it.
  func testAccountsRowCountsActiveAccountsAndTotalsThemWithoutArchived() throws {
    let spy = SpyInsightsStore()
    spy.summaries = [
      summary("Savings", tracked: 100_000),
      summary("Card", kindRaw: "card", tracked: -20_000),
      summary("Old", tracked: 50_000, archived: true),
    ]
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: spy)

    model.loadAccounts()

    let accounts = try XCTUnwrap(model.accounts)
    XCTAssertEqual(accounts.state, .loaded)
    XCTAssertEqual(accounts.active.count, 2)
    XCTAssertEqual(accounts.totalMinor, 80_000)
  }

  func testAFailedAccountsReadIsTheFailedStateNotAZeroTotal() throws {
    let spy = SpyInsightsStore()
    spy.failSummaries = true
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: spy)

    model.loadAccounts()

    XCTAssertEqual(try XCTUnwrap(model.accounts).state, .failed)
  }

  /// With no store there is nothing to read, so there is no Accounts model at all.
  func testWithoutAnInsightsStoreThereIsNoAccountsRead() {
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: nil)

    model.loadAccounts()

    XCTAssertNil(model.accounts)
  }

  // MARK: - S9a step 2: Export everything

  /// The file is named as Insights names its exports, holds every transaction in the
  /// store's answer, and is removed by the same call Insights uses.
  func testExportEverythingWritesAnAllTimeCSVFile() throws {
    let spy = SpyInsightsStore()
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: spy)

    let url = try model.exportEverything(names: CSVNameMaps(categories: [:], accounts: [:]))
    defer { ReportsCSVExport.remove(url) }

    XCTAssertTrue(url.lastPathComponent.hasPrefix("nomi-report-"))
    XCTAssertEqual(url.pathExtension, "csv")
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertEqual(spy.periodsRequested, [.allTime])
  }

  func testExportWithoutAStoreWritesNothing() {
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: nil)

    XCTAssertThrowsError(try model.exportEverything(names: CSVNameMaps(categories: [:], accounts: [:])))
  }

  /// A read that fails must not leave an empty CSV behind that looks like a real export.
  func testExportReadFailureIsThrownAndWritesNoFile() {
    let spy = SpyInsightsStore()
    spy.failTransactions = true
    let model = SettingsModel(storeRecovery: nil, recoveryDefaults: defaults, insightsStore: spy)

    XCTAssertThrowsError(try model.exportEverything(names: CSVNameMaps(categories: [:], accounts: [:])))
  }

  // MARK: - Helpers

  private final class SpyInsightsStore: InsightsStore {
    var summaries: [AccountSummary] = []
    var failSummaries = false
    var failTransactions = false
    private(set) var periodsRequested: [InsightPeriod] = []

    func insights(for period: InsightPeriod) throws -> PeriodInsights { throw SpyFailure() }
    func trend(months: Int) throws -> [MonthBucket] { [] }
    func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] {
      if failSummaries { throw SpyFailure() }
      return summaries
    }
    func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
    func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] {
      periodsRequested.append(period)
      if failTransactions { throw SpyFailure() }
      return []
    }
    func unassignedTransactions() throws -> [NomiCore.Transaction] { [] }
  }

  private func summary(
    _ name: String,
    kindRaw: String = "bank",
    tracked: Int,
    archived: Bool = false
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(),
      displayName: name,
      institution: "Bank",
      lastFour: "0000",
      kindRaw: kindRaw,
      trackedBalanceMinor: tracked,
      transactionCount: 0,
      trackingSince: nil,
      isArchived: archived
    )
  }
}
