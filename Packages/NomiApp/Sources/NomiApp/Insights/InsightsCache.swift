import Combine
import Foundation
import NomiCore

/// Every aggregate the app can ask for, as a hashable key.
///
/// `InsightPeriod` is `Hashable` and *value*-addressed — `month(year:month:)`
/// rather than `month(anchor: Date)` — precisely so it can key this cache
/// (design §2.3). A `Date` anchor would produce a different key for every
/// second of the same month and the cache would never hit.
public enum InsightsCacheKey: Hashable, Sendable {
  case insights(InsightPeriod)
  case trend(months: Int)
  case accountSummaries(includeArchived: Bool)
  case budgetProgress(year: Int, month: Int)
  case transactions(InsightPeriod)
  case recent(limit: Int)
}

/// R14's "cached per period and invalidated on write", as a thing by itself.
///
/// It is `@MainActor` and generic over `Any` rather than typed per method
/// because the alternative — five typed dictionaries — is five places to
/// forget to clear. **Invalidation is all-or-nothing on purpose.** Clearing
/// only the affected period sounds tighter and is wrong: a write moves a
/// transaction between categories, which changes `byCategory` for the period,
/// `budgetProgress` for its month, `trend` for the enclosing year and
/// `accountSummaries` for all time. Working out that closure correctly on every
/// write path is exactly the kind of bookkeeping that goes stale silently, and
/// a stale dashboard is a wrong number shown confidently.
///
/// The cost of being coarse is one recompute per write batch, not per row: the
/// pipeline commits once per batch (`CommitPlan`), and the observer fires once
/// per commit.
@MainActor
public final class InsightsCache: ObservableObject {
  private var storage: [InsightsCacheKey: Any] = [:]

  /// Bumped on every invalidation, and the *only* published property here.
  ///
  /// It is what makes the dashboard redraw after a background sync. The screens
  /// that read aggregates (`DashboardView`, `ReportsScreen`, the ledger) hold
  /// no `@Query` and compute their numbers in `body`, so SwiftData's own change
  /// tracking never reaches them — without an observable signal they would show
  /// whatever was true when they were last re-rendered for an unrelated reason.
  ///
  /// `missCount` deliberately is not published: it is mutated *during* body
  /// evaluation, and publishing from there is the "Publishing changes from
  /// within view updates" warning at best and a render loop at worst.
  @Published public private(set) var generation = 0

  /// Counts recomputes. Not diagnostics for their own sake — it is the only
  /// way a test can assert "the second read did not hit the store", which is
  /// the whole behaviour R14 asks for and is otherwise invisible.
  public private(set) var missCount = 0
  public private(set) var invalidationCount = 0

  public init() {}

  public func value<T>(for key: InsightsCacheKey, compute: () throws -> T) rethrows -> T {
    if let cached = storage[key] as? T {
      return cached
    }
    missCount += 1
    let fresh = try compute()
    storage[key] = fresh
    return fresh
  }

  public func invalidate() {
    storage.removeAll(keepingCapacity: true)
    invalidationCount += 1
    generation += 1
  }

  public var isEmpty: Bool { storage.isEmpty }
}
