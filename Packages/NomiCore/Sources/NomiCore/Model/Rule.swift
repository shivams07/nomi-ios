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

  /// The four scope columns (§W2-5). Optional for the same reason `isSystem`
  /// carries a default: the store is CloudKit-backed, so a new property must
  /// be optional or defaulted to avoid a migration pass, and `nil` is also the
  /// right answer for every row written before scoping existed — it reads back
  /// as `RuleScope.any`, which is what those rules have always meant.
  ///
  /// Stored flat rather than as an encoded `RuleScope` blob so each one stays
  /// a column a `#Predicate` could narrow on later. `scope` below is the only
  /// thing that should read them.
  public var directionRaw: String?
  public var accountID: UUID?
  public var minAmountMinor: Int?
  public var maxAmountMinor: Int?

  public var createdAt: Date = Date()

  public init(
    id: UUID = UUID(),
    pattern: String = "",
    categoryID: UUID = UUID(),
    priority: Int = 0,
    isEnabled: Bool = true,
    isSystem: Bool = false,
    scope: RuleScope = .any,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.pattern = pattern
    self.categoryID = categoryID
    self.priority = priority
    self.isEnabled = isEnabled
    self.isSystem = isSystem
    directionRaw = scope.direction?.rawValue
    accountID = scope.accountID
    minAmountMinor = scope.minAmountMinor
    maxAmountMinor = scope.maxAmountMinor
    self.createdAt = createdAt
  }
}

extension Rule {
  /// The four columns as one value.
  ///
  /// In an extension rather than the class body because a stored `@Model`
  /// property and a computed one with the same standing read identically at
  /// the call site, and only one of them is persisted. Keeping the bridge out
  /// here makes the persisted set exactly the list above it.
  ///
  /// An unreadable `directionRaw` — a value no `Direction` case has, which
  /// only a hand-edited store or a future case could produce — reads as `nil`,
  /// meaning "either direction". The alternative is a rule that silently
  /// admits nothing, and a rule that has stopped firing is much harder to
  /// notice than one that fires too widely.
  public var scope: RuleScope {
    get {
      RuleScope(
        direction: directionRaw.flatMap(Direction.init(rawValue:)),
        accountID: accountID,
        minAmountMinor: minAmountMinor,
        maxAmountMinor: maxAmountMinor
      )
    }
    set {
      directionRaw = newValue.direction?.rawValue
      accountID = newValue.accountID
      minAmountMinor = newValue.minAmountMinor
      maxAmountMinor = newValue.maxAmountMinor
    }
  }
}
