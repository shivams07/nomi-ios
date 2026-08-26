import Foundation
import SwiftData

/// A shared, in-memory `ModelContainer`/`ModelContext` for use wherever `@Model`
/// instances are constructed outside of the app's real persistent store —
/// `NomiPreview`'s fakes and `NomiCoreTests`. SwiftData's macro-generated backing
/// storage requires an active container even for detached, never-persisted
/// instances; without one, property access crashes at runtime.
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

  /// Inserts `model` into the shared context and returns it, for tests and
  /// callers that construct `@Model` instances without going through a store.
  @discardableResult
  public static func inserted<T: PersistentModel>(_ model: T) -> T {
    context.insert(model)
    return model
  }
}
