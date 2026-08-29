import Foundation
import NomiCore
import NomiPreview
import SwiftData

/// Preview-only `ModelContainer` scaffolding, same convention as
/// `EntryRulesPreviewSupport`: a FRESH in-memory container per call, never
/// `InMemoryModelContainer.shared` (process-wide, would accumulate rows
/// across canvas runs). Not exercised by `swift test` — SwiftData's headless
/// bundle-name lookup fails before any of this runs (see
/// `InMemoryModelContainer`'s note in NomiCore) — these helpers are for
/// Xcode canvas / on-device preview use, which this team cannot run locally
/// either; real verification is Shivam's.
enum LedgerPreviewSupport {
  @MainActor
  static func makeContainer(
    transactions: [NomiCore.Transaction] = PreviewData.transactions,
    categories: [NomiCore.Category] = PreviewData.categories,
    accounts: [NomiCore.Account] = PreviewData.accounts
  ) -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Transaction.self, NomiCore.Category.self, NomiCore.Account.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    for category in categories { container.mainContext.insert(category) }
    for account in accounts { container.mainContext.insert(account) }
    for transaction in transactions { container.mainContext.insert(transaction) }
    return container
  }

  private static func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: string)!
  }

  /// One row, so the "single-day ledger" preview has exactly one day group
  /// and no others to accidentally satisfy the AC against.
  static func singleDayTransactions() -> [NomiCore.Transaction] {
    let day = date("2026-08-20")
    let description = "SWIGGY/PAYMENT/REF1"
    let normalized = normalizeDescription(description)
    return [
      NomiCore.Transaction(
        date: day,
        descriptionText: description,
        merchantName: "SWIGGY",
        normalizedDescription: normalized,
        amountMinor: 45_00,
        directionRaw: Direction.debit.rawValue,
        categoryID: PreviewData.categories[0].id,
        categorySourceRaw: CategorySource.rule.rawValue,
        accountID: PreviewData.accounts[0].id,
        sourceRaw: IngestSource.email.rawValue,
        dedupeKey: makeDedupeKey(
          date: day, amountMinor: 45_00, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
        ),
        createdAt: day,
        updatedAt: day
      ),
    ]
  }

  /// Spans 31 Dec 2025 -> 2 Jan 2026 so the "month spanning a year boundary"
  /// AC has an actual boundary to cross, rather than relying on whatever
  /// `PreviewData`'s relative-to-now data happens to include this month.
  static func yearBoundaryTransactions() -> [NomiCore.Transaction] {
    ["2025-12-31", "2026-01-01", "2026-01-02"].enumerated().map { index, dateString in
      let day = date(dateString)
      let description = "ZOMATO/PAYMENT/REF\(index)"
      let normalized = normalizeDescription(description)
      return NomiCore.Transaction(
        date: day,
        descriptionText: description,
        merchantName: "ZOMATO",
        normalizedDescription: normalized,
        amountMinor: 32_00,
        directionRaw: Direction.debit.rawValue,
        categoryID: PreviewData.categories[0].id,
        categorySourceRaw: CategorySource.rule.rawValue,
        accountID: PreviewData.accounts[0].id,
        sourceRaw: IngestSource.email.rawValue,
        dedupeKey: makeDedupeKey(
          date: day, amountMinor: 32_00, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
        ),
        createdAt: day,
        updatedAt: day
      )
    }
  }
}
