import Foundation
import SwiftData

@Model
public final class Rule {
  public var id: UUID = UUID()
  public var pattern: String = ""
  public var categoryID: UUID = UUID()
  public var priority: Int = 0
  public var isEnabled: Bool = true

  /// A rule `DefaultRuleSeed` put here, rather than one the user wrote.
  ///
  /// Additive with a default, which is what keeps this a lightweight migration:
  /// the store is CloudKit-backed, and CloudKit requires every new property to
  /// be optional or carry a default, so existing rows read back as `false`
  /// without a migration pass. `false` is also the right answer for them —
  /// every row written before this property existed came from the user or from
  /// a seed that predates the flag, and `DefaultRuleSeed.apply` backfills the
  /// second case by id on the next launch.
  ///
  /// It gates deletion, not editing. A user may still rename a system rule's
  /// pattern, retarget it, reorder it or disable it; they may not delete it,
  /// because a deleted id is indistinguishable from one that was never seeded
  /// and the seed would put it straight back on the next launch. Disabling is
  /// the affordance that actually sticks.
  public var isSystem: Bool = false

  public var createdAt: Date = Date()

  public init(
    id: UUID = UUID(),
    pattern: String = "",
    categoryID: UUID = UUID(),
    priority: Int = 0,
    isEnabled: Bool = true,
    isSystem: Bool = false,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.pattern = pattern
    self.categoryID = categoryID
    self.priority = priority
    self.isEnabled = isEnabled
    self.isSystem = isSystem
    self.createdAt = createdAt
  }
}
