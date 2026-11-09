#if DEBUG && (targetEnvironment(simulator) || os(macOS))
import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// The demo dataset, and the seeder that writes it through the stores.
///
/// XCTest, not swift-testing: the seeder builds real `@Model` rows in an
/// in-memory container (see `InMemoryModelContainer`). Each test keeps its
/// `InMemoryStack` in a property, so the container outlives the context.
///
/// The expectations are computed here from the value list, in IST, by code that
/// does not share the builder's month arithmetic. A fixed `today` is used
/// throughout: 9 November 2026, which is also the day this was written.
@MainActor
final class DemoDataTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  private let today: Date = NomiCalendar.india.date(
    from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))!

  private var dataset: DemoDataset { DemoDataset.make(today: today) }

  // MARK: - The value list, on its own

  func testTheDatasetIsTheSameEveryTimeForTheSameDay() {
    XCTAssertEqual(DemoDataset.make(today: today), DemoDataset.make(today: today))
  }

  func testTheDatasetCoversThreeMonthsAndAboutFiftyRows() {
    let rows = dataset.rows
    let months = Set(rows.map { monthKey($0.date) })
    XCTAssertEqual(months, ["2026-09", "2026-10", "2026-11"])

    // Stored rows are every row but the one the pipeline merges away.
    let stored = rows.filter { $0.absorbedInto == nil }
    XCTAssertTrue((45...60).contains(stored.count), "stored rows: \(stored.count)")
  }

  func testNoRowIsDatedAfterToday() {
    // Compared by IST day, not instant: rows sit at noon and `today` is 10:00,
    // so an instant comparison would reject today's own rows.
    let todayStart = NomiCalendar.india.startOfDay(for: today)
    for row in dataset.rows {
      XCTAssertLessThanOrEqual(NomiCalendar.india.startOfDay(for: row.date), todayStart, row.id)
    }
  }

  func testEveryRowIsNoonInIndiaSoNoTimezoneMovesItADay() {
    for row in dataset.rows {
      let hour = NomiCalendar.india.component(.hour, from: row.date)
      XCTAssertEqual(hour, 12, row.id)
    }
  }

  /// DEC-05: the two legs of one card payment are the same amount, one debit and
  /// one credit, on different accounts, the credit side a card.
  func testTheTransferPairIsEqualAndOpposite() {
    let legs = dataset.rows.filter { $0.pairID == "nov-card-bill" }
    XCTAssertEqual(legs.count, 2)
    guard let debit = legs.first(where: { $0.direction == .debit }),
      let credit = legs.first(where: { $0.direction == .credit })
    else {
      return XCTFail("a pair needs one debit leg and one credit leg")
    }
    XCTAssertEqual(debit.amountMinor, credit.amountMinor)
    XCTAssertEqual(debit.date, credit.date)
    XCTAssertNotEqual(debit.accountKey, credit.accountKey)
    XCTAssertEqual(debit.accountKey, "hdfc")
    XCTAssertEqual(credit.accountKey, "icici")
    XCTAssertEqual(
      dataset.accounts.first { $0.key == credit.accountKey }?.kind, .card)
  }

  /// Every reason the pipeline can set, each on at least one row. The switch has
  /// no default, so a new `NeedsReviewReason` case stops this file compiling
  /// until the dataset covers it.
  func testEveryNeedsReviewReasonIsOnARow() {
    func covered(_ reason: NeedsReviewReason) -> Bool {
      switch reason {
      case .unidentifiedAccount, .heuristic, .unparseable, .unreadableDate,
        .unauthenticatedSender, .foreignCurrency:
        return true
      }
    }
    let reasons = dataset.rows.compactMap { row -> NeedsReviewReason? in
      if case .reason(let reason) = row.review { return reason }
      return nil
    }
    for reason in [
      NeedsReviewReason.unidentifiedAccount, .heuristic, .unparseable, .unreadableDate,
      .unauthenticatedSender, .foreignCurrency,
    ] {
      XCTAssertTrue(covered(reason))
      XCTAssertTrue(reasons.contains(reason), "no row carries \(reason)")
    }
  }

  func testTheDatasetOnlyNamesSeededCategoriesAndDeclaredAccounts() {
    let names = Set(DefaultCategorySeed.specs.map(\.name))
    let keys = Set(dataset.accounts.map(\.key))
    for budget in dataset.budgets {
      XCTAssertTrue(names.contains(budget.categoryName), budget.categoryName)
    }
    for rule in dataset.rules {
      XCTAssertTrue(names.contains(rule.categoryName), rule.categoryName)
      if let key = rule.accountKey { XCTAssertTrue(keys.contains(key), key) }
    }
    for row in dataset.rows {
      if let name = row.categoryName { XCTAssertTrue(names.contains(name), name) }
      if let key = row.accountKey { XCTAssertTrue(keys.contains(key), key) }
    }
  }

  /// The variable is read only in a Debug simulator build. Everywhere else the
  /// answer is `false`, whatever the environment holds.
  func testTheVariableIsReadOnlyInASimulatorDebugBuild() {
    XCTAssertFalse(DemoDataSeeder.isRequested(in: [:]))
    XCTAssertFalse(DemoDataSeeder.isRequested(in: ["NOMI_DEMO_DATA": "0"]))
    #if targetEnvironment(simulator)
      XCTAssertTrue(DemoDataSeeder.isRequested(in: ["NOMI_DEMO_DATA": "1"]))
    #else
      XCTAssertFalse(DemoDataSeeder.isRequested(in: ["NOMI_DEMO_DATA": "1"]))
    #endif
  }

  // MARK: - Seeding through the stores

  func testSeedingAnEmptyStoreWritesEveryAccountBudgetRuleAndRow() async throws {
    let environment = try makeEnvironment()
    let written = try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    XCTAssertTrue(written)

    let accounts = try environment.insightsStore.accountSummaries(includeArchived: true)
    XCTAssertEqual(Set(accounts.map(\.displayName)), ["HDFC Savings", "ICICI Credit Card", "Cash Wallet"])
    let hdfc = try XCTUnwrap(accounts.first { $0.displayName == "HDFC Savings" })
    XCTAssertEqual(hdfc.openingBalanceMinor, 12_000_000, "₹1,20,000.00 in paise")

    XCTAssertEqual(try environment.budgetStore.budgets().count, dataset.budgets.count)
    XCTAssertEqual(try rules(environment).filter { !$0.isSystem }.count, dataset.rules.count)

    let stored = try allTransactions(environment)
    XCTAssertEqual(stored.count, dataset.rows.filter { $0.absorbedInto == nil }.count)
  }

  /// The idempotence the task asks for: a second run into the same store writes
  /// nothing, and the counts do not move.
  func testApplyingTwiceDoesNotDuplicate() async throws {
    let environment = try makeEnvironment()
    let first = try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    let rowsAfterFirst = try allTransactions(environment).count
    let accountsAfterFirst = try environment.insightsStore.accountSummaries(includeArchived: true).count

    let second = try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))

    XCTAssertTrue(first)
    XCTAssertFalse(second)
    XCTAssertEqual(try allTransactions(environment).count, rowsAfterFirst)
    XCTAssertEqual(
      try environment.insightsStore.accountSummaries(includeArchived: true).count, accountsAfterFirst)
  }

  /// The guard also covers accounts: a store that holds an account and no
  /// transactions is the user's own data, and it must not gain a second set of
  /// accounts or any rows.
  func testAStoreWithOnlyAnAccountIsLeftAlone() async throws {
    let environment = try makeEnvironment()
    _ = try environment.accountStore.create(
      displayName: "Mine", institution: "Bank", lastFour: "1234", kindRaw: "bank")

    let written = try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))

    XCTAssertFalse(written)
    XCTAssertEqual(try environment.insightsStore.accountSummaries(includeArchived: true).count, 1)
    XCTAssertEqual(try allTransactions(environment).count, 0)
  }

  /// Each row lands in the category the dataset names, with the account, the
  /// review state and the reason the dataset gives. Categories come from the real
  /// rule pass, so this is also a test that the rules agree with the dataset.
  func testSeededRowsLandWhereTheDatasetSaysAndTheRulesAgree() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    let stored = try allTransactions(environment)
    let ids = categoryIDs()
    let accountIDs = try accountIDsByKey(environment)

    for row in dataset.rows {
      switch row.route {
      case .pipeline:
        if row.absorbedInto != nil {
          // The absorbed leg's own ref is on the row it merged into.
          let merged = try XCTUnwrap(
            stored.first(where: { transaction in
              transaction.sourceRefs.contains { $0.externalID == row.id }
            }),
            "the row absorbing \(row.id) is missing")
          XCTAssertEqual(merged.mergedCount, 2, row.id)
          XCTAssertEqual(merged.sourceRefs.first?.externalID, row.absorbedInto, row.id)
          continue
        }
        let transaction = try XCTUnwrap(
          stored.first { $0.sourceRefs.first?.externalID == row.id }, row.id)
        XCTAssertEqual(transaction.amountMinor, row.amountMinor, row.id)
        XCTAssertEqual(transaction.direction, row.direction, row.id)
        XCTAssertEqual(transaction.currencyCode, row.currencyCode, row.id)
        XCTAssertEqual(transaction.categoryID, row.categoryName.flatMap { ids[$0] }, row.id)
        XCTAssertEqual(transaction.accountID, row.accountKey.flatMap { accountIDs[$0] }, row.id)
        XCTAssertEqual(transaction.needsReview, row.review.isFlagged, row.id)
        if case .reason(let reason) = row.review {
          XCTAssertEqual(transaction.needsReviewReason, reason, row.id)
        }
      case .manual:
        let transaction = try XCTUnwrap(
          stored.first { $0.descriptionText == row.narration && $0.amountMinor == row.amountMinor },
          row.id)
        XCTAssertEqual(transaction.categoryID, row.categoryName.flatMap { ids[$0] }, row.id)
        XCTAssertEqual(transaction.accountID, row.accountKey.flatMap { accountIDs[$0] }, row.id)
      }
    }
  }

  /// The near duplicate (DEC-13) collapses into one row that is flagged for
  /// review, and the second copy is not stored on its own.
  func testTheNearDuplicateMergesIntoOneFlaggedRow() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))

    let swiggy = try allTransactions(environment).filter { $0.descriptionText == "DINE OUT/SWIGGY/REF2" }
    XCTAssertEqual(swiggy.count, 1)
    XCTAssertEqual(swiggy.first?.mergedCount, 2)
    XCTAssertEqual(swiggy.first?.needsReview, true)
    XCTAssertEqual(swiggy.first?.needsReviewReason, nil)
  }

  /// DEC-05 end to end: the pipeline's detector marks the card payment as one
  /// pair, auto, and both legs share the group.
  func testTheCardPaymentIsDetectedAsATransferPair() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))

    let legs = try allTransactions(environment).filter {
      $0.descriptionText == "NEFT CC PAYMENT ICICI CARD" || $0.descriptionText == "PAYMENT RECEIVED THANK YOU"
    }
    XCTAssertEqual(legs.count, 2)
    XCTAssertTrue(legs.allSatisfy(\.isTransfer))
    XCTAssertEqual(Set(legs.compactMap(\.transferGroupID)).count, 1)
    XCTAssertTrue(legs.allSatisfy { $0.transferSource == .auto })
  }

  /// The Rules artboard's scoped rule (#106, #109) is stored with its scope.
  func testTheScopedRuleKeepsItsScope() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    let hdfcID = try XCTUnwrap(try accountIDsByKey(environment)["hdfc"])

    let payroll = try XCTUnwrap(try rules(environment).first { $0.pattern == "*ACME PAYROLL*" })
    XCTAssertEqual(payroll.scope, RuleScope(direction: .credit, accountID: hdfcID))
  }

  // MARK: - Home, Budgets, Subscriptions: the real aggregator over the seeded rows

  /// The totals for November, from the value list alone. A transfer leg, a
  /// foreign-currency row and a merged-away copy are kept out of the money, as
  /// DEC-05 and U18 say, and the review and uncategorized counts are taken over
  /// the whole month the way the aggregator takes them.
  func testHomeTotalsMatchHandComputedExpectations() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    let insights = try insightsStore(environment).insights(for: .month(year: 2026, month: 11))

    let month = dataset.rows.filter { monthKey($0.date) == "2026-11" && $0.absorbedInto == nil }
    let counted = month.filter { $0.currencyCode == "INR" && $0.pairID == nil }
    let expectedDebit = counted.filter { $0.direction == .debit }.reduce(0) { $0 + $1.amountMinor }
    let expectedCredit = counted.filter { $0.direction == .credit }.reduce(0) { $0 + $1.amountMinor }

    XCTAssertEqual(insights.debitMinor, expectedDebit)
    XCTAssertEqual(insights.creditMinor, expectedCredit)
    XCTAssertEqual(insights.netMinor, expectedCredit - expectedDebit)
    XCTAssertEqual(insights.transactionCount, counted.count)
    XCTAssertEqual(insights.needsReviewCount, month.filter { $0.review.isFlagged }.count)
    XCTAssertEqual(
      insights.uncategorizedCount,
      month.filter { $0.pairID == nil && $0.categoryName == nil }.count)

    // The same figures, written out, so a change to the list shows up as a number.
    XCTAssertEqual(insights.debitMinor, Self.expectedNovemberDebitMinor)
    XCTAssertEqual(insights.creditMinor, Self.expectedNovemberCreditMinor)
  }

  /// Each budget's spend is the counted debits in its category, and the three
  /// states the artboards show are all present: one under, one near, one over.
  func testBudgetsMatchHandComputedSpendAndCoverEachState() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))
    let progress = try insightsStore(environment).budgetProgress(year: 2026, month: 11)

    let month = dataset.rows.filter { monthKey($0.date) == "2026-11" && $0.absorbedInto == nil }
    for budget in dataset.budgets {
      let row = try XCTUnwrap(progress.first { $0.categoryName == budget.categoryName })
      let expectedSpent = month
        .filter {
          $0.currencyCode == "INR" && $0.pairID == nil && $0.direction == .debit
            && $0.categoryName == budget.categoryName
        }
        .reduce(0) { $0 + $1.amountMinor }
      XCTAssertEqual(row.budgetMinor, budget.amountMinor, budget.categoryName)
      XCTAssertEqual(row.spentMinor, expectedSpent, budget.categoryName)
    }

    let state = { (name: String) -> String in
      let fraction = progress.first { $0.categoryName == name }?.fraction ?? 0
      if fraction > 1 { return "over" }
      if fraction >= 0.9 { return "near" }
      return "under"
    }
    XCTAssertEqual(state("UPI & Food Delivery"), "under")
    XCTAssertEqual(state("Shopping"), "near")
    XCTAssertEqual(state("Ride-hailing"), "over")
    XCTAssertEqual(state("Groceries"), "under")
  }

  /// The recurring series the Subscriptions screen reads: Netflix and Rent each
  /// have the three monthly debits the detector needs.
  func testTheRecurringSeriesAreDetected() async throws {
    let environment = try makeEnvironment()
    try await DemoDataSeeder.seedIfEmpty(dataset, into: stores(environment))

    let series = try RecurrenceDetector.series(
      in: try allTransactions(environment).map { row in
        RecurrenceRow(
          date: row.date, amountMinor: row.amountMinor, directionRaw: row.directionRaw,
          normalizedDescription: row.normalizedDescription, merchantName: row.merchantName,
          descriptionText: row.descriptionText, isTransfer: row.isTransfer)
      },
      now: today, calendar: NomiCalendar.india)

    let names = Set(series.map(\.id))
    XCTAssertTrue(names.contains("NETFLIX.COM"), "\(names)")
    XCTAssertTrue(names.contains("NEFT RENT RAJESH KUMAR"), "\(names)")
  }

  // MARK: - Helpers

  /// Hand-summed from the November rows of the list: 20 counted INR rows (the card-payment
  /// legs, the USD row and the merged-away copy are left out). Debits ₹35,318.00, credits ₹38,500.00.
  private static let expectedNovemberDebitMinor = 3_531_800
  private static let expectedNovemberCreditMinor = 3_850_000

  private func makeEnvironment() throws -> AppEnvironment {
    let stack = try InMemoryStack()
    stacks.append(stack)
    try DefaultCategorySeed.apply(in: stack.container.mainContext)
    try DefaultRuleSeed.apply(in: stack.container.mainContext)
    return AppEnvironment(
      container: stack.container,
      preferences: InMemoryKeyValueStore(),
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler()
    )
  }

  /// The composition's stores, with a pipeline over the same container. The
  /// composition's own pipeline is private to `AppEnvironment`.
  private func stores(_ environment: AppEnvironment) -> DemoDataSeeder.Stores {
    DemoDataSeeder.Stores(
      transactions: environment.transactionStore,
      accounts: environment.accountStore,
      rules: environment.ruleStore,
      budgets: environment.budgetStore,
      insights: environment.insightsStore,
      pipeline: IngestPipeline(store: SwiftDataPipelineStore(modelContainer: environment.container)))
  }

  /// The Insights store on Indian calendar months, so the figures are the same
  /// on any machine. The composition uses `Calendar.current`, which is the same
  /// for every row here because each sits at noon IST.
  private func insightsStore(_ environment: AppEnvironment) throws -> SwiftDataInsightsStore {
    SwiftDataInsightsStore(
      context: environment.container.mainContext,
      cache: environment.cache,
      calendar: NomiCalendar.india,
      now: { self.today })
  }

  private func allTransactions(_ environment: AppEnvironment) throws -> [Transaction] {
    try environment.insightsStore.transactions(in: .allTime)
  }

  private func rules(_ environment: AppEnvironment) throws -> [Rule] {
    try environment.container.mainContext.fetch(FetchDescriptor<Rule>())
  }

  private func accountIDsByKey(_ environment: AppEnvironment) throws -> [String: UUID] {
    let accounts = try environment.container.mainContext.fetch(FetchDescriptor<Account>())
    var byName: [String: UUID] = [:]
    for account in accounts {
      switch account.displayName {
      case "HDFC Savings": byName["hdfc"] = account.id
      case "ICICI Credit Card": byName["icici"] = account.id
      case "Cash Wallet": byName["cash"] = account.id
      default: break
      }
    }
    return byName
  }

  private func categoryIDs() -> [String: UUID] {
    Dictionary(uniqueKeysWithValues: DefaultCategorySeed.specs.map { ($0.name, $0.id) })
  }

  /// `"YYYY-MM"` in IST, read from the calendar components, not the builder's
  /// arithmetic.
  private func monthKey(_ date: Date) -> String {
    let parts = NomiCalendar.india.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
  }
}
#endif
