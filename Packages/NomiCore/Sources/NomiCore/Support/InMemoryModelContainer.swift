import Foundation
import SwiftData

/// SwiftData's macro-generated backing storage requires an active
/// `ModelContainer` even for detached, never-persisted instances — property
/// access crashes without one. `inserted(_:)` gives every model its own
/// in-memory container so concurrent callers (parallel test execution,
/// `NomiPreview`'s static seed data) never share a single `ModelContext`,
/// which SwiftData does not guarantee is safe to mutate concurrently. Each
/// container is retained for the process lifetime so the model stays backed.
public enum InMemoryModelContainer {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var retainedContainers: [ModelContainer] = []

  private static let schema = Schema([
    Transaction.self,
    Category.self,
    Budget.self,
    BudgetAlertLog.self,
    Rule.self,
    Account.self,
    AccountBinding.self,
    ColumnMappingRecord.self,
  ])

  @discardableResult
  public static func inserted<T: PersistentModel>(_ model: T) -> T {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    context.insert(model)

    lock.lock()
    retainedContainers.append(container)
    lock.unlock()

    return model
  }
}
