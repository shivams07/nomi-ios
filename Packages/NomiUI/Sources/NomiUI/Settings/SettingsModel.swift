import Foundation
import NomiCore
import Observation

/// The Settings screen's mail scans and store-recovery notice, outside the view
/// (T2a), so plain XCTest can drive them with a spy service. The screen owns one
/// through `@State`. Scan copy and the scan calls are `SettingsActions`' own.
@Observable @MainActor final class SettingsModel {
  @ObservationIgnored let service: MailConnectionService
  @ObservationIgnored private let recoveryDefaults: UserDefaults

  private(set) var isRescanning = false
  private(set) var isScanningRecent = false
  private(set) var lastSyncSummary: SyncSummary?
  var rescanError: String?
  /// R7's notice. Cleared by `dismissStoreRecovery`, which hides the row here too.
  private(set) var storeRecovery: StoreRecoveryNotice?

  init(service: MailConnectionService, storeRecovery: StoreRecoveryNotice?, recoveryDefaults: UserDefaults) {
    self.service = service
    self.storeRecovery = storeRecovery
    self.recoveryDefaults = recoveryDefaults
  }

  /// "Force re-scan": `syncNow()` and nothing else. The `do/catch` surfaces every
  /// re-scan failure as an alert. A `try?` here once swallowed a wrong password,
  /// a dropped socket and a server refusal alike, and left the button springing back.
  @discardableResult
  func rescan() -> Task<Void, Never> {
    isRescanning = true
    rescanError = nil
    return Task {
      defer { isRescanning = false }
      do {
        lastSyncSummary = try await SettingsActions.rescan(using: service)
      } catch {
        rescanError = SettingsActions.alertText(for: error)
      }
    }
  }

  /// "Scan last 6 months": its own loading flag, but the same summary and alert
  /// as `rescan()`.
  @discardableResult
  func scanRecent() -> Task<Void, Never> {
    isScanningRecent = true
    rescanError = nil
    return Task {
      defer { isScanningRecent = false }
      do {
        lastSyncSummary = try await SettingsActions.scanRecent(using: service)
      } catch {
        rescanError = SettingsActions.alertText(for: error)
      }
    }
  }

  /// Dismiss on the store-recovery notice: forgets the record and hides the row.
  func dismissStoreRecovery() {
    StoreRecoveryRecord.clear(in: recoveryDefaults)
    storeRecovery = nil
  }
}
