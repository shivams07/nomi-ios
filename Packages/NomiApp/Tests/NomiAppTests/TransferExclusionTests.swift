import Foundation
import NomiCore
import Testing

@testable import NomiApp

// clt-harness: include

/// DEC-05 and A-05, at the aggregator, over `LedgerRow` values. No SwiftData, so
/// it runs on the CLT harness. Fixture F is the one the decisions file names:
/// savings S (opening 1,00,000.00), card C (opening 0.00); November rows, all
/// INR: C debit 20,000.00 "Amazon"; S debit 20,000.00 "HDFC CREDIT CARD PAYMENT"
/// on 10 Nov; C credit 20,000.00 "PAYMENT RECEIVED - THANK YOU" on 11 Nov.
/// Amounts are paise. The SwiftData side is in XCTest and deferred.
struct TransferExclusionTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private let savings = UUID()
  private let card = UUID()
  private let food = UUID()

  /// Noon IST on the given day of the given month, 2026.
  private func day(_ dayOfMonth: Int, month: Int = 11) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = month
    components.day = dayOfMonth
    components.hour = 12
    return calendar.date(from: components)!
  }

  private func row(
    _ amount: Int,
    _ direction: Direction = .debit,
    on date: Date,
    category: UUID? = nil,
    account: UUID? = nil,
    normalized: String = "MERCHANT",
    needsReview: Bool = false,
    currency: String = "INR",
    transfer: Bool = false
  ) -> LedgerRow {
    LedgerRow(
      id: UUID(),
      date: date,
      amountMinor: amount,
      directionRaw: direction.rawValue,
      categoryID: category,
      accountID: account,
      normalizedDescription: normalized,
      merchantName: nil,
      descriptionText: normalized,
      needsReview: needsReview,
      currencyCode: currency,
      isTransfer: transfer
    )
  }

  /// A copy of `source` with its transfer flag set. `LedgerRow` is a value, so a
  /// mark is a new value, which is how these tests mark and unmark.
  private func marked(_ source: LedgerRow, _ flag: Bool) -> LedgerRow {
    LedgerRow(
      id: source.id,
      date: source.date,
      amountMinor: source.amountMinor,
      directionRaw: source.directionRaw,
      categoryID: source.categoryID,
      accountID: source.accountID,
      normalizedDescription: source.normalizedDescription,
      merchantName: source.merchantName,
      descriptionText: source.descriptionText,
      needsReview: source.needsReview,
      currencyCode: source.currencyCode,
      isTransfer: flag
    )
  }

  private func accounts() -> [AccountRef] {
    [
      AccountRef(
        id: savings, displayName: "Savings", institution: "HDFC", lastFour: "1111",
        kindRaw: "bank", isArchived: false, openingBalanceMinor: 1_00_000_00),
      AccountRef(
        id: card, displayName: "Card", institution: "HDFC", lastFour: "6411",
        kindRaw: "card", isArchived: false, openingBalanceMinor: 0),
    ]
  }

  /// Fixture F's rows. `amazon` has no category, which is what makes the
  /// uncategorised-count test meaningful.
  private struct FixtureF {
    let amazon: LedgerRow
    let savingsDebit: LedgerRow
    let cardCredit: LedgerRow
    var rows: [LedgerRow] { [amazon, savingsDebit, cardCredit] }
  }

  private func fixtureF(legsMarked: Bool) -> FixtureF {
    let amazon = row(2_000_000, .debit, on: day(1), account: card, normalized: "AMAZON")
    let sDebit = row(
      2_000_000, .debit, on: day(10), account: savings, normalized: "HDFC CREDIT CARD PAYMENT",
      transfer: legsMarked)
    let cCredit = row(
      2_000_000, .credit, on: day(11), account: card, normalized: "PAYMENT RECEIVED - THANK YOU",
      transfer: legsMarked)
    return FixtureF(amazon: amazon, savingsDebit: sDebit, cardCredit: cCredit)
  }

  private func november(_ rows: [LedgerRow]) -> PeriodInsights {
    InsightsAggregator.insights(
      period: .month(year: 2026, month: 11), rows: rows, categories: [:], priorRows: nil, calendar: calendar)
  }

  // MARK: - A-05 item 1: no double counting (fixture F)

  @Test func fixtureFBeforeMarkingCountsTheBillTwice() {
    let insights = november(fixtureF(legsMarked: false).rows)
    #expect(insights.debitMinor == 4_000_000)
    #expect(insights.creditMinor == 2_000_000)
    #expect(insights.netMinor == -2_000_000)
  }

  @Test func fixtureFAfterMarkingThePairCountsEachMoneyMovementOnce() {
    let insights = november(fixtureF(legsMarked: true).rows)
    #expect(insights.debitMinor == 2_000_000)
    #expect(insights.creditMinor == 0)
    #expect(insights.netMinor == -2_000_000)
  }

  // MARK: - A-05 item 2: net is conserved; a straddling pair shifts each month by its own leg

  @Test func aPairStraddlingAMonthBoundaryMovesEachMonthByItsOwnLeg() {
    let octoberLeg = row(2_000_000, .debit, on: day(31, month: 10), account: savings, normalized: "HDFC CC")
    let novemberLeg = row(2_000_000, .credit, on: day(1), account: card, normalized: "PAYMENT RECEIVED")
    let unmarked = [octoberLeg, novemberLeg]
    let markedRows = [marked(octoberLeg, true), marked(novemberLeg, true)]

    let octoberBefore = InsightsAggregator.insights(
      period: .month(year: 2026, month: 10), rows: [unmarked[0]], categories: [:], priorRows: nil, calendar: calendar)
    let octoberAfter = InsightsAggregator.insights(
      period: .month(year: 2026, month: 10), rows: [markedRows[0]], categories: [:], priorRows: nil, calendar: calendar)
    let novemberBefore = november([unmarked[1]])
    let novemberAfter = november([markedRows[1]])

    #expect(octoberAfter.debitMinor - octoberBefore.debitMinor == -2_000_000)
    #expect(novemberAfter.creditMinor - novemberBefore.creditMinor == -2_000_000)
    let netDelta = (octoberAfter.netMinor - octoberBefore.netMinor) + (novemberAfter.netMinor - novemberBefore.netMinor)
    #expect(netDelta == 0, "marking a pair conserves net across the two months it touches")
  }

  // MARK: - A-05 item 3: balances unchanged

  @Test func fixtureFBalancesAreUnchangedByMarking() {
    let before = InsightsAggregator.accountSummaries(
      accounts: accounts(), rows: fixtureF(legsMarked: false).rows, includeArchived: true)
    let after = InsightsAggregator.accountSummaries(
      accounts: accounts(), rows: fixtureF(legsMarked: true).rows, includeArchived: true)

    #expect(before.map(\.trackedBalanceMinor) == after.map(\.trackedBalanceMinor))
    let savingsAfter = after.first { $0.id == savings }
    let cardAfter = after.first { $0.id == card }
    #expect(savingsAfter?.trackedBalanceMinor == 8_000_000, "S 80,000.00")
    #expect(cardAfter?.trackedBalanceMinor == 0, "C 0.00")
    #expect(after.map(\.trackedBalanceMinor).reduce(0, +) == 8_000_000, "total 80,000.00")
  }

  /// A-05 item 3 over generated ledgers. A fixed seed, so a failure reproduces.
  @Test func accountSummariesAreIdenticalAcrossAnyMarkingOfAGeneratedLedger() {
    var generator = FixedSeedGenerator(state: 0xC0FFEE)
    let accountIDs: [UUID?] = [savings, card, nil]
    var rows: [LedgerRow] = []
    for _ in 0..<300 {
      let direction: Direction = generator.nextInt(2) == 0 ? .debit : .credit
      let amount = 100 + generator.nextInt(500_000)
      let dayOfMonth = 1 + generator.nextInt(28)
      let monthNumber = generator.nextInt(2) == 0 ? 10 : 11
      let account = accountIDs[generator.nextInt(accountIDs.count)]
      let currency = generator.nextInt(10) == 0 ? "USD" : "INR"
      rows.append(
        row(amount, direction, on: day(dayOfMonth, month: monthNumber), account: account,
            currency: currency, transfer: generator.nextInt(3) == 0))
    }
    let baseline = summaryFields(rows)

    var marks = rows
    for index in marks.indices where generator.nextInt(2) == 0 {
      marks[index] = marked(marks[index], !marks[index].isTransfer)
    }
    #expect(summaryFields(marks) == baseline, "any marking leaves every account balance unchanged")

    let unmarked = marks.map { marked($0, false) }
    #expect(summaryFields(unmarked) == baseline, "unmarking everything leaves them unchanged too")
  }

  private func summaryFields(_ rows: [LedgerRow]) -> [String] {
    InsightsAggregator.accountSummaries(accounts: accounts(), rows: rows, includeArchived: true).map {
      "\($0.id)|\($0.trackedBalanceMinor)|\($0.transactionCount)|\(String(describing: $0.trackingSince))"
    }
  }

  // MARK: - A-05 item 4: reversible

  @Test func unmarkingRestoresEveryAggregateExactly() {
    let f = fixtureF(legsMarked: false)
    let before = november(f.rows)
    let beforeTrend = InsightsAggregator.trend(rows: f.rows, calendar: calendar).map { [$0.debitMinor, $0.creditMinor] }

    let markedRows = fixtureF(legsMarked: true).rows
    _ = november(markedRows)
    let restoredRows = markedRows.map { marked($0, false) }
    let restored = november(restoredRows)

    #expect(restored.debitMinor == before.debitMinor)
    #expect(restored.creditMinor == before.creditMinor)
    #expect(restored.netMinor == before.netMinor)
    #expect(restored.transactionCount == before.transactionCount)
    #expect(restored.uncategorizedCount == before.uncategorizedCount)
    #expect(restored.byDay.map(\.debitMinor) == before.byDay.map(\.debitMinor))
    #expect(restored.topMerchants.map(\.totalMinor) == before.topMerchants.map(\.totalMinor))
    let restoredTrend = InsightsAggregator.trend(rows: restoredRows, calendar: calendar).map { [$0.debitMinor, $0.creditMinor] }
    #expect(restoredTrend == beforeTrend)
  }

  // MARK: - A-05 item 10: one test per row of the exclusion table

  @Test func transfersAreOutOfTheDebitAndCreditTotals() {
    let transfer = row(5_000_000, .debit, on: day(3), account: savings, transfer: true)
    let spend = row(100_000, .debit, on: day(4), account: card)
    let insights = november([transfer, spend])
    #expect(insights.debitMinor == 100_000)
    #expect(insights.netMinor == -100_000)
  }

  @Test func transfersAreOutOfTheTransactionCount() {
    let rows = [
      row(5_000_000, .debit, on: day(3), transfer: true),
      row(5_000_000, .credit, on: day(3), transfer: true),
      row(100_000, .debit, on: day(4)),
    ]
    #expect(november(rows).transactionCount == 1)
  }

  @Test func transfersAreOutOfByDayByCategoryAndTopMerchants() {
    let transfer = row(5_000_000, .debit, on: day(3), category: food, normalized: "HDFC CC", transfer: true)
    let spend = row(100_000, .debit, on: day(3), category: food, normalized: "SWIGGY")
    let insights = november([transfer, spend])
    #expect(insights.byDay.map(\.debitMinor) == [100_000])
    #expect(insights.byCategory.map(\.totalMinor) == [100_000])
    #expect(insights.topMerchants.map(\.totalMinor) == [100_000])
  }

  @Test func transfersAreOutOfUncategorizedCount() {
    let f = fixtureF(legsMarked: false)
    #expect(november(f.rows).uncategorizedCount == 3, "before: the Amazon debit and both legs")
    #expect(november(fixtureF(legsMarked: true).rows).uncategorizedCount == 1, "after: only Amazon")
  }

  @Test func transfersAreOutOfThePriorPeriodComparison() {
    let priorTransfer = row(5_000_000, .debit, on: day(3, month: 10), transfer: true)
    let priorSpend = row(100_000, .debit, on: day(4, month: 10))
    let insights = InsightsAggregator.insights(
      period: .month(year: 2026, month: 11), rows: [], categories: [:],
      priorRows: [priorTransfer, priorSpend], calendar: calendar)
    #expect(insights.priorDebitMinor == 100_000)
  }

  @Test func transfersAreOutOfTheTrend() {
    let rows = [
      row(5_000_000, .debit, on: day(3), transfer: true),
      row(100_000, .debit, on: day(4)),
    ]
    let buckets = InsightsAggregator.trend(rows: rows, calendar: calendar)
    #expect(buckets.map(\.debitMinor) == [100_000])
  }

  @Test func transfersAreOutOfTheBudgetProgress() {
    let budget = BudgetRef(categoryID: food, amountMinor: 5_000_000, isEnabled: true)
    let transfer = row(1_000_000, .debit, on: day(3), category: food, transfer: true)
    let markedProgress = InsightsAggregator.budgetProgress(
      budgets: [budget], rows: [transfer], categories: [:], periodKey: "2026-11")
    #expect(markedProgress.first?.spentMinor == 0)

    let plain = InsightsAggregator.budgetProgress(
      budgets: [budget], rows: [marked(transfer, false)], categories: [:], periodKey: "2026-11")
    #expect(plain.first?.spentMinor == 1_000_000, "the same row, unmarked, is spend")
  }

  @Test func transfersStillCountInNeedsReview() {
    let flagged = row(5_000_000, .debit, on: day(3), needsReview: true, transfer: true)
    #expect(november([flagged]).needsReviewCount == 1, "a transfer still needs its review")
  }

  @Test func transfersStillCountInAccountSummaries() {
    let transfer = row(5_000_000, .debit, on: day(3), account: savings, transfer: true)
    let summary = InsightsAggregator.accountSummaries(accounts: accounts(), rows: [transfer], includeArchived: false)
    #expect(summary.first { $0.id == savings }?.transactionCount == 1)
    #expect(summary.first { $0.id == savings }?.trackedBalanceMinor == 1_00_000_00 - 5_000_000)
  }

  // MARK: -

  /// The debit-only figure the spoken summary reads (`insights.debitMinor`).
  @Test func theSpokenSummaryFigureExcludesTransfers() {
    let rows = [row(5_000_000, .debit, on: day(3), transfer: true), row(250_000, .debit, on: day(4))]
    #expect(november(rows).debitMinor == 250_000)
  }
}

/// A fixed-seed generator (SplitMix64-style), so the generated ledger is the
/// same on every run and every machine.
private struct FixedSeedGenerator {
  var state: UInt64

  mutating func nextInt(_ bound: Int) -> Int {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z = z ^ (z >> 31)
    return Int(z % UInt64(bound))
  }
}
