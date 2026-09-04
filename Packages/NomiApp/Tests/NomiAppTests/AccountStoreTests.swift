import Foundation
import NomiCore
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// An account the user creates must be visible on the screen they created it
/// from, on the render right after they tap Save.
///
/// Nothing on the Accounts screen or the dashboard reads `Account` directly.
/// Both go through `InsightsStore.accountSummaries`, which is cache-gated:
/// `InsightsCache` holds the last answer and only `WriteCoordinator.didWrite`
/// drops it. So `create` has two halves that look like one — the save, and the
/// invalidation — and a `create` with only the save is correct in the store and
/// invisible in the app until some unrelated write happens to clear the cache.
///
/// That is why these tests assert the *summaries* and not just a fetch. A fetch
/// goes straight at the context and passes either way.
///
/// A `ModelContainer` under `swift test` is fine in XCTest and traps under
/// swift-testing — see `InMemoryModelContainer` — which is why this is XCTest,
/// like `RulePriorityTests` next to it.
@MainActor
final class AccountStoreTests: XCTestCase {

  // MARK: - The real store

  /// The whole unit, in one test: create, then read the summaries through a
  /// cache that was already warm.
  ///
  /// The warm-up read is not scene-setting. Without it the cache is empty, the
  /// read after `create` is a miss whatever `didWrite` did, and this test goes
  /// green with the invalidation deleted — which is the one thing it exists to
  /// catch. `testTheCacheIsRealAndWouldServeAStaleAnswer` pins that the warm-up
  /// actually warms.
  func testACreatedAccountIsFetchableAndReachesTheSummariesThroughAWarmCache() throws {
    let (store, context, cache) = try makeStore()
    let insights = SwiftDataInsightsStore(context: context, cache: cache)

    XCTAssertTrue(
      try insights.accountSummaries(includeArchived: false).isEmpty,
      "the cache is warm from here on, holding an empty answer")

    let created = try store.create(
      displayName: "HDFC 4471",
      institution: "HDFC Bank",
      lastFour: "4471",
      kindRaw: "bank"
    )

    let fetched = try context.fetch(FetchDescriptor<Account>())
    XCTAssertEqual(fetched.map(\.id), [created.id], "the row is persisted")

    let summaries = try insights.accountSummaries(includeArchived: false)
    XCTAssertEqual(
      summaries.map(\.displayName), ["HDFC 4471"],
      "a missing didWrite leaves the cached empty answer in place and this is []")
    XCTAssertEqual(summaries.map(\.id), [created.id])
  }

  /// The control for the test above: the cache it leans on is real, and a save
  /// that skips `didWrite` really is invisible through it.
  ///
  /// If this ever fails, the warm-up in the previous test stopped warming and
  /// its assertion stopped meaning anything — it would be passing on a fresh
  /// computation rather than on the invalidation.
  func testTheCacheIsRealAndWouldServeAStaleAnswer() throws {
    let (store, context, cache) = try makeStore()
    let insights = SwiftDataInsightsStore(context: context, cache: cache)

    _ = try insights.accountSummaries(includeArchived: false)
    let missesAfterFirstRead = cache.missCount

    // A row inserted behind the back of the store: saved, but with no didWrite.
    // This is exactly the shape of a create that forgot to invalidate.
    context.insert(Account(displayName: "Invisible", institution: "", lastFour: "", kindRaw: "bank"))
    try context.save()

    XCTAssertTrue(
      try insights.accountSummaries(includeArchived: false).isEmpty,
      "a save without didWrite is invisible — the bug create must not have")
    XCTAssertEqual(
      cache.missCount, missesAfterFirstRead,
      "and it was invisible because the answer was cached, not because it was absent")

    // The same row becomes visible the moment something invalidates.
    try store.create(displayName: "Anything", institution: "", lastFour: "", kindRaw: "bank")
    XCTAssertEqual(
      try insights.accountSummaries(includeArchived: false).count, 2,
      "didWrite drops the cache for every account, not just the created one")
  }

  /// A created account is active, so it appears with `includeArchived: false`.
  /// `Account.isArchived` defaults to false and `create` passes nothing for it;
  /// this pins that, because a default flipped in the model would empty the
  /// Accounts screen with no other test here noticing.
  func testACreatedAccountIsActiveNotArchived() throws {
    let (store, context, cache) = try makeStore()
    let insights = SwiftDataInsightsStore(context: context, cache: cache)

    let created = try store.create(
      displayName: "ICICI 8890",
      institution: "ICICI Bank",
      lastFour: "8890",
      kindRaw: "card"
    )

    XCTAssertFalse(created.isArchived)
    XCTAssertEqual(try insights.accountSummaries(includeArchived: false).map(\.id), [created.id])

    let stored = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first)
    XCTAssertEqual(stored.institution, "ICICI Bank")
    XCTAssertEqual(stored.lastFour, "8890")
    XCTAssertEqual(
      stored.kindRaw, "card", "every field the caller passed is stored, not just the name")
  }

  // MARK: - The fake store must agree

  /// The preview stack must not disagree with production about what `create`
  /// does. Both stores start from the same two accounts, both create the same
  /// third, and both must end with the same count and the same names.
  func testBothStoresAgreeOnCountAndDisplayNameAfterCreate() throws {
    let starting = ["HDFC 4471", "ICICI 8890"]

    let (store, context, _) = try makeStore()
    for name in starting {
      context.insert(Account(displayName: name, institution: "", lastFour: "", kindRaw: "bank"))
    }
    try context.save()

    let fake = FakeAccountStore(
      accounts: starting.map {
        Account(displayName: $0, institution: "", lastFour: "", kindRaw: "bank")
      })

    try store.create(
      displayName: "Axis 1002", institution: "Axis Bank", lastFour: "1002", kindRaw: "card")
    try fake.create(
      displayName: "Axis 1002", institution: "Axis Bank", lastFour: "1002", kindRaw: "card")

    let real = try context.fetch(FetchDescriptor<Account>())
    XCTAssertEqual(real.count, fake.accounts.count, "the two stores disagree on count")
    XCTAssertEqual(
      real.map(\.displayName).sorted(), fake.accounts.map(\.displayName).sorted(),
      "the two stores disagree on what was created")
  }

  /// `FakeAccountStore.create` appends to `accounts` and hands back that same
  /// instance, which is what lets a preview build `FakeInsightsStore` from the
  /// store afterwards and see the new row. A fake that returned a copy, or kept
  /// created accounts anywhere but `accounts`, would give every preview an
  /// Accounts screen where creating does nothing — the same failure the real
  /// `didWrite` prevents, demonstrated everywhere the previews are.
  func testFakeCreateAppendsTheInstanceItReturnsSoTheFakeSummariesIncludeIt() throws {
    let fake = FakeAccountStore(accounts: [])

    let created = try fake.create(
      displayName: "Axis 1002", institution: "Axis Bank", lastFour: "1002", kindRaw: "card")

    XCTAssertEqual(fake.accounts.count, 1)
    XCTAssertTrue(fake.accounts[0] === created, "the appended account must be the returned one")

    let insights = FakeInsightsStore(transactions: [], accounts: fake.accounts)
    XCTAssertEqual(try insights.accountSummaries(includeArchived: false).map(\.id), [created.id])
  }

  // MARK: -

  /// A fresh container per test, and one `InsightsCache` shared by the store
  /// that writes and the store that reads — sharing it is the point, since a
  /// second cache would make `didWrite` invisible to the reader and every
  /// assertion here would be about nothing.
  ///
  /// Deliberately not `InMemoryModelContainer.shared`: these tests count rows.
  private func makeStore() throws -> (SwiftDataAccountStore, ModelContext, InsightsCache) {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    let context = container.mainContext
    let cache = InsightsCache()
    let store = SwiftDataAccountStore(context: context, coordinator: WriteCoordinator(cache: cache))
    return (store, context, cache)
  }
}
