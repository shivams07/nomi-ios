import Foundation
import SwiftData

/// An in-memory `ModelContainer` for `NomiApp` to hand to `NomiPreview`/UI
/// previews and, on-device, for anything that needs a scratch container.
///
/// NOT usable from `swift test` in this CI. SwiftData's CoreData-backed store
/// resolves a bundle name on first load — `SwiftData/DataStoreCoreData.swift:32:
/// Fatal error: Unable to determine Bundle Name` — and a headless `swift test`
/// binary has no app bundle to resolve. That is true regardless of
/// `isStoredInMemoryOnly`, `cloudKitDatabase`, or store URL: none of those
/// configuration knobs avoid the bundle-name lookup. The only known fix is
/// embedding an `Info.plist` into the test binary via target `linkerSettings`
/// in `Package.swift` (see the escalation note in this unit's PR) — out of
/// this unit's file boundary, since `Package.swift` is frozen by U0. Until
/// that lands, tests and `NomiPreview` must not construct `@Model` instances;
/// `TransactionCSVExporter.row(...)` is the pattern other tests should follow
/// — a pure function decoupled from the `@Model` type it normally serves.
public enum InMemoryModelContainer {
  public static let shared: ModelContainer = {
    let schema = Schema([
      Transaction.self,
      Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try! ModelContainer(for: schema, configurations: [configuration])
  }()
}
