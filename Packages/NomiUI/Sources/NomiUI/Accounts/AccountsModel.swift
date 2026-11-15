import Foundation
import NomiCore
import Observation

/// The Accounts screen's read, outside the view (S8 step 3), so plain XCTest can
/// drive it with a spy. One `load()` reads the summaries, archived included, and
/// the unassigned count. A read that throws makes the whole screen `.failed`: a
/// wrong total must not look right, so nothing from a half-read is kept.
@Observable @MainActor final class AccountsModel {
  enum State: Equatable {
    case loading
    case loaded
    case failed
  }

  @ObservationIgnored private let insightsStore: InsightsStore

  private(set) var state: State = .loading
  private(set) var active: [AccountSummary] = []
  private(set) var archived: [AccountSummary] = []
  /// The signed sum of the active accounts' tracked balances. Archived ones are not in it.
  private(set) var totalMinor = 0
  /// The earliest tracking start among the active accounts; nil when none has a transaction yet.
  private(set) var trackingSince: Date?
  /// Rows with no account, transfers included (I-10).
  private(set) var unassignedCount = 0

  init(insightsStore: InsightsStore) {
    self.insightsStore = insightsStore
  }

  func load() {
    do {
      let summaries = try insightsStore.accountSummaries(includeArchived: true)
      let unassigned = try insightsStore.unassignedTransactions().count
      let activeAccounts = AccountSectioning.active(summaries)
      active = activeAccounts
      archived = AccountSectioning.archived(summaries)
      totalMinor = AccountBalanceDisplay.total(
        summaries.map { (isArchived: $0.isArchived, trackedMinor: $0.trackedBalanceMinor) }
      )
      trackingSince = activeAccounts.compactMap(\.trackingSince).min()
      unassignedCount = unassigned
      state = .loaded
    } catch {
      active = []
      archived = []
      totalMinor = 0
      trackingSince = nil
      unassignedCount = 0
      state = .failed
    }
  }
}
