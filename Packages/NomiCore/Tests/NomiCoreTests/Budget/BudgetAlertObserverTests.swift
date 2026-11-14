import Foundation
import Testing

@testable import NomiCore

/// One actor plays both seams so the interleaving of "log it" and "show it" is
/// observable in a single ordered list.
private actor RecordingHarness: BudgetAlertContextProviding, BudgetNotificationScheduling {
  enum Event: Equatable {
    case readContext
    case recorded([String])
    case scheduled(String)
  }

  private(set) var events: [Event] = []
  private let context: BudgetAlertContext
  private let authorized: Bool
  private let failsToSchedule: Bool

  init(context: BudgetAlertContext, authorized: Bool = true, failsToSchedule: Bool = false) {
    self.context = context
    self.authorized = authorized
    self.failsToSchedule = failsToSchedule
  }

  func currentContext() async -> BudgetAlertContext {
    events.append(.readContext)
    return context
  }

  func recordFired(_ alerts: [BudgetAlert]) async {
    events.append(.recorded(alerts.map(\.logKey)))
  }

  func requestAuthorization() async throws -> Bool { true }

  func isAuthorized() async -> Bool { authorized }

  struct Refused: Error {}

  func schedule(_ alert: BudgetAlert) async throws {
    if failsToSchedule { throw Refused() }
    events.append(.scheduled(alert.logKey))
  }
}

struct BudgetAlertObserverTests {
  private let groceries = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
  private let rent = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

  private func progress(
    _ categoryID: UUID,
    name: String,
    spentMinor: Int,
    periodKey: String = "2026-08"
  ) -> BudgetProgress {
    BudgetProgress(
      id: categoryID,
      categoryName: name,
      paletteSlot: 0,
      budgetMinor: 1_000_000,
      spentMinor: spentMinor,
      fraction: Double(spentMinor) / 1_000_000,
      periodKey: periodKey
    )
  }

  private func harness(
    _ progress: [BudgetProgress],
    firedKeys: Set<String> = [],
    enabled: Bool = true,
    authorized: Bool = true,
    failsToSchedule: Bool = false
  ) -> RecordingHarness {
    RecordingHarness(
      context: BudgetAlertContext(
        progress: progress,
        firedKeys: firedKeys,
        settings: NotificationSettings(budgetAlertsEnabled: enabled, thresholdFraction: 0.9)
      ),
      authorized: authorized,
      failsToSchedule: failsToSchedule
    )
  }

  /// Recording happens after the centre accepts the alert. The old order
  /// recorded first, so a refused alert still closed the category for the month.
  @Test func recordsOnlyAfterSchedulingSucceeds() async {
    let key = BudgetAlertEvaluator.logKey(categoryID: groceries, periodKey: "2026-08")

    let accepted = harness([progress(groceries, name: "Groceries", spentMinor: 920_000)])
    await BudgetAlertObserver(context: accepted, scheduler: accepted)
      .didCommit(affectedCategoryIDs: [groceries])
    let acceptedEvents = await accepted.events
    #expect(acceptedEvents == [.readContext, .scheduled(key), .recorded([key])])

    let refused = harness(
      [progress(groceries, name: "Groceries", spentMinor: 920_000)],
      failsToSchedule: true
    )
    await BudgetAlertObserver(context: refused, scheduler: refused)
      .didCommit(affectedCategoryIDs: [groceries])
    let refusedEvents = await refused.events
    #expect(refusedEvents == [.readContext, .recorded([])])
  }

  /// No permission means no notification and no log row. The alert stays open
  /// for the month and fires on a later commit once permission exists.
  @Test func unauthorisedRecordsNothingAndSchedulesNothing() async {
    let fake = harness(
      [progress(groceries, name: "Groceries", spentMinor: 920_000)],
      authorized: false
    )
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [groceries])

    let events = await fake.events
    #expect(events == [.readContext])
  }

  @Test func onlyCategoriesTouchedByTheCommitAreConsidered() async {
    let fake = harness([
      progress(groceries, name: "Groceries", spentMinor: 920_000),
      progress(rent, name: "Rent", spentMinor: 950_000),
    ])
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [rent])

    let rentKey = BudgetAlertEvaluator.logKey(categoryID: rent, periodKey: "2026-08")
    let events = await fake.events
    #expect(events == [.readContext, .scheduled(rentKey), .recorded([rentKey])])
  }

  @Test func anEmptyCommitBatchDoesNotEvenReadTheContext() async {
    let fake = harness([progress(groceries, name: "Groceries", spentMinor: 920_000)])
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [])

    let events = await fake.events
    #expect(events.isEmpty)
  }

  @Test func nothingIsLoggedWhenNothingCrossed() async {
    let fake = harness([progress(groceries, name: "Groceries", spentMinor: 100_000)])
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [groceries])

    let events = await fake.events
    #expect(events == [.readContext])
  }

  @Test func aSecondCommitInTheSameMonthSchedulesNothing() async {
    let key = BudgetAlertEvaluator.logKey(categoryID: groceries, periodKey: "2026-08")
    let fake = harness(
      [progress(groceries, name: "Groceries", spentMinor: 990_000)],
      firedKeys: [key]
    )
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [groceries])

    let events = await fake.events
    #expect(events == [.readContext])
  }

  @Test func disabledSettingsScheduleNothing() async {
    let fake = harness(
      [progress(groceries, name: "Groceries", spentMinor: 5_000_000)],
      enabled: false
    )
    let observer = BudgetAlertObserver(context: fake, scheduler: fake)

    await observer.didCommit(affectedCategoryIDs: [groceries])

    let events = await fake.events
    #expect(events == [.readContext])
  }

  @Test func aSuppressedAlertIsRejectedByTheScheduler() async throws {
    let alert = BudgetAlert(
      categoryID: groceries,
      categoryName: "Groceries",
      periodKey: "2026-08",
      budgetMinor: 1_000_000,
      spentMinor: 920_000,
      fraction: 0.92,
      wasSuppressed: true
    )

    await #expect(throws: BudgetNotificationError.suppressedAlertMustNotBeScheduled) {
      try await BudgetNotificationScheduler().schedule(alert)
    }
  }

  @Test func notificationBodyReadsAsPercentage() {
    let under = BudgetAlert(
      categoryID: groceries, categoryName: "Groceries", periodKey: "2026-08",
      budgetMinor: 1_000_000, spentMinor: 920_000, fraction: 0.92, wasSuppressed: false
    )
    let over = BudgetAlert(
      categoryID: groceries, categoryName: "Groceries", periodKey: "2026-08",
      budgetMinor: 1_000_000, spentMinor: 1_200_000, fraction: 1.2, wasSuppressed: false
    )

    #expect(BudgetNotificationScheduler.body(for: under) == "You've used 92% of this month's budget.")
    #expect(BudgetNotificationScheduler.body(for: over) == "You're over budget — 120% spent.")
  }
}
