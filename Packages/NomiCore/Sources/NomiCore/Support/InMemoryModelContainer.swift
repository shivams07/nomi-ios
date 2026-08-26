import Foundation
import SwiftData

/// SwiftData's macro-generated backing storage requires an active
/// `ModelContainer` to exist BEFORE any `@Model` instance is constructed —
/// even a detached, never-persisted one. `warmUp()` must run as its own
/// statement ahead of any `Transaction()`/`Category()`/etc. call site
/// (constructing a model as a nested call argument evaluates too late,
/// since Swift evaluates arguments before entering the callee). Used by
/// `NomiPreview`'s seed data and by `NomiCoreTests`.
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
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
  }()

  public static let context: ModelContext = ModelContext(shared)

  /// Forces the container to exist. Call this as its own statement before
  /// constructing any `@Model` instance.
  public static func warmUp() {
    _ = shared
  }

  @discardableResult
  public static func inserted<T: PersistentModel>(_ model: T) -> T {
    context.insert(model)
    return model
  }
}
