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
  /// Total entries held. Thirty-two covers every aggregate a user can reach in
  /// one session several times over - twelve months of `insights`, a handful of
  /// trends, both `accountSummaries` flags, a year of `budgetProgress` - so the
  /// bound is never felt in normal use. It exists for the case that is not
  /// normal: a reports screen scrubbed backwards through, one entry per month,
  /// forever, with nothing but `invalidate()` ever freeing any of it.
  static let capacity = 32

  /// `.transactions` entries hold **live `@Model` references**, not value
  /// types - a `.transactions(.allTime)` entry pins the entire ledger. Four is
  /// deliberately much tighter than the general bound because the cost per
  /// entry is unbounded rather than small.
  ///
  /// `.recent(limit:)` also holds rows and is deliberately *not* in this
  /// bucket: it is bounded by its own `limit`, and its only caller asks for
  /// five.
  static let transactionCapacity = 4

  private var storage: [InsightsCacheKey: Any] = [:]

  /// Recency order, least-recently-used first. A parallel array rather than
  /// anything cleverer: Foundation has no ordered dictionary, and at
  /// thirty-two elements a linear `firstIndex(of:)` costs less than the
  /// bookkeeping an intrusive list would need.
  private var recency: [InsightsCacheKey] = []

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
      touch(key)
      return cached
    }
    missCount += 1
    let fresh = try compute()
    storage[key] = fresh
    touch(key)
    evictIfNeeded(after: key)
    return fresh
  }

  public func invalidate() {
    storage.removeAll(keepingCapacity: true)
    recency.removeAll(keepingCapacity: true)
    invalidationCount += 1
    generation += 1
  }

  public var isEmpty: Bool { storage.isEmpty }

  /// Entries currently held. Exists so a test can assert the bound; nothing in
  /// the app reads it.
  var count: Int { storage.count }

  // MARK: - Eviction

  /// Moves `key` to the most-recently-used end. Called on a **hit** as well as
  /// an insert: without that, the value a screen reads on every render would
  /// still be the first one dropped, which is the opposite of what LRU is for.
  private func touch(_ key: InsightsCacheKey) {
    if let existing = recency.firstIndex(of: key) {
      recency.remove(at: existing)
    }
    recency.append(key)
  }

  /// Evicts oldest-first until both bounds hold.
  ///
  /// The `.transactions` bound is checked only when a `.transactions` entry was
  /// just added - no other insert can push that bucket over - and it evicts
  /// only entries of that same kind, so a full-ledger read cannot flush the
  /// aggregates the screen around it is mid-render on.
  private func evictIfNeeded(after inserted: InsightsCacheKey) {
    if case .transactions = inserted {
      var held = recency.filter {
        if case .transactions = $0 { return true } else { return false }
      }
      while held.count > Self.transactionCapacity {
        drop(held.removeFirst())
      }
    }

    while storage.count > Self.capacity, let oldest = recency.first {
      drop(oldest)
    }
  }

  private func drop(_ key: InsightsCacheKey) {
    storage.removeValue(forKey: key)
    if let index = recency.firstIndex(of: key) {
      recency.remove(at: index)
    }
  }
}
