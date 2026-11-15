import Foundation
import SwiftData

/// The app's schema, as version 1.
///
/// This is the **only** list of the app's models. `NomiModelContainer.schema`
/// and `InMemoryModelContainer.shared` both read it, so a model cannot be
/// present in one store and missing from the other.
///
/// Wrapping the existing models changes no entity, property or hash, so a
/// store written before versioning opens under V1 without a migration stage.
/// `StoreMigrationTests` proves that on a real file.
///
/// Both members are computed `static var`s, not stored, so there is no global
/// mutable state for strict concurrency to object to.
public enum NomiSchemaV1: VersionedSchema {
  public static var versionIdentifier: Schema.Version {
    Schema.Version(1, 0, 0)
  }

  public static var models: [any PersistentModel.Type] {
    [
      Transaction.self,
      Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ]
  }
}

/// The migration plan the app's stores open with. V1 is the only schema, so
/// there are no stages yet. A future V2 adds its schema to `schemas` and its
/// stage to `stages`; until then an unknown store version is a failed open,
/// which `NomiModelContainer.makeWithLocalFallback` moves aside rather than
/// deletes.
public enum NomiMigrationPlan: SchemaMigrationPlan {
  public static var schemas: [any VersionedSchema.Type] {
    [NomiSchemaV1.self]
  }

  public static var stages: [MigrationStage] {
    []
  }
}
