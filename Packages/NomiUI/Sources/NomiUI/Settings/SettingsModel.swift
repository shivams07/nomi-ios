import Foundation
import NomiCore
import Observation

/// The Settings screen's store-recovery notice, the Accounts row's read and the
/// "Export everything" file, outside the view (T2a, S9a), so plain XCTest can drive
/// them. The screen owns one through `@State`. The mail scans moved to Connect mail
/// (S12b), so nothing here calls the mail service any more.
@Observable @MainActor final class SettingsModel {
  /// The export failed before a file was written: there is no store to read from.
  enum ExportError: Error, Equatable {
    case unavailable
  }

  @ObservationIgnored private let recoveryDefaults: UserDefaults
  @ObservationIgnored private let insightsStore: InsightsStore?

  /// R7's notice. Cleared by `dismissStoreRecovery`, which hides the row here too.
  private(set) var storeRecovery: StoreRecoveryNotice?
  /// The Accounts row's count and total, read the way the Accounts screen reads them.
  /// `nil` when Settings was given no insights store, so there is nothing to read.
  private(set) var accounts: AccountsModel?

  init(storeRecovery: StoreRecoveryNotice?, recoveryDefaults: UserDefaults, insightsStore: InsightsStore? = nil) {
    self.storeRecovery = storeRecovery
    self.recoveryDefaults = recoveryDefaults
    self.insightsStore = insightsStore
    self.accounts = insightsStore.map { AccountsModel(insightsStore: $0) }
  }

  /// Reads the Accounts row again. Called when the screen appears and whenever the
  /// refresh token changes.
  func loadAccounts() {
    accounts?.load()
  }

  /// Dismiss on the store-recovery notice: forgets the record and hides the row.
  func dismissStoreRecovery() {
    StoreRecoveryRecord.clear(in: recoveryDefaults)
    storeRecovery = nil
  }

  /// "Export everything": every transaction, written to a CSV the share sheet can
  /// send. It reads the same way Insights' export does, with the all-time period.
  /// The caller removes the file when its share sheet closes (`ReportsCSVExport.remove`).
  func exportEverything(names: CSVNameMaps) throws -> URL {
    guard let insightsStore else { throw ExportError.unavailable }
    let transactions = try insightsStore.transactions(in: .allTime)
    return try ReportsCSVExport.write(
      transactions, names: names, periodLabel: ReportsPeriod.label(for: .allTime))
  }
}
