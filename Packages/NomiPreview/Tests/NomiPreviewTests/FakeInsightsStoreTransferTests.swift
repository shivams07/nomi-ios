import Foundation
import NomiCore
import XCTest

@testable import NomiPreview

/// DEC-05 A-05 item 10, the `FakeInsightsStore` row. The fake mirrors the
/// aggregator's exclusions, so a preview cannot disagree with the app about a
/// mark. Fixture F in November 2025, so `trend` sees it.
///
/// XCTest, `@MainActor`, as the fake is. Minor units throughout: 20,000.00 is
/// 2_000_000.
@MainActor
final class FakeInsightsStoreTransferTests: XCTestCase {

  private let savings = UUID()
  private let card = UUID()
  private let shopping = UUID()
  private let group = TransferGroupID.make(single: UUID())

  private func date(_ day: Int) -> Date {
    var components = DateComponents()
    components.year = 2025
    components.month = 11
    components.day = day
    components.hour = 12
    return Calendar.current.date(from: components)!
  }

  /// The three rows of fixture F, unmarked. The caller marks what it needs.
  private func fixtureF() -> (amazon: Transaction, savingsDebit: Transaction, cardCredit: Transaction) {
    let amazon = Transaction(
      date: date(5),
      descriptionText: "Amazon",
      normalizedDescription: "AMAZON",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      categoryID: shopping,
      accountID: card,
      dedupeKey: "amazon"
    )
    let savingsDebit = Transaction(
      date: date(10),
      descriptionText: "HDFC CREDIT CARD PAYMENT",
      normalizedDescription: "HDFC CREDIT CARD PAYMENT",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      categoryID: shopping,
      accountID: savings,
      needsReview: true,
      dedupeKey: "savings"
    )
    let cardCredit = Transaction(
      date: date(11),
      descriptionText: "PAYMENT RECEIVED - THANK YOU",
      normalizedDescription: "PAYMENT RECEIVED - THANK YOU",
      amountMinor: 2_000_000,
      directionRaw: Direction.credit.rawValue,
      accountID: card,
      dedupeKey: "card"
    )
    return (amazon, savingsDebit, cardCredit)
  }

  private func store(_ rows: [Transaction]) -> FakeInsightsStore {
    FakeInsightsStore(
      transactions: rows,
      categories: [NomiCore.Category(id: shopping, name: "Shopping", paletteSlot: 1)],
      accounts: [
        Account(
          id: savings, displayName: "Savings", institution: "HDFC", lastFour: "1111",
          kindRaw: "bank", isArchived: false, openingBalanceMinor: 10_000_000),
        Account(
          id: card, displayName: "Card", institution: "HDFC", lastFour: "6411",
          kindRaw: "card", isArchived: false, openingBalanceMinor: 0),
      ],
      budgets: [Budget(categoryID: shopping, amountMinor: 5_000_000)]
    )
  }

  func testUnmarkedFixtureFCountsTheBillTwice() throws {
    let f = fixtureF()
    let fake = store([f.amazon, f.savingsDebit, f.cardCredit])

    let insights = try fake.insights(for: .month(year: 2025, month: 11))
    XCTAssertEqual(insights.debitMinor, 4_000_000)
    XCTAssertEqual(insights.creditMinor, 2_000_000)
    XCTAssertEqual(insights.netMinor, -2_000_000)
    XCTAssertEqual(insights.uncategorizedCount, 1, "the card credit has no category")
    XCTAssertEqual(insights.needsReviewCount, 1)

    let shoppingRow = try XCTUnwrap(
      try fake.budgetProgress(year: 2025, month: 11).first { $0.id == shopping })
    XCTAssertEqual(shoppingRow.spentMinor, 4_000_000)
  }

  func testAMarkedPairIsOutOfEveryFigureButReviewAndBalances() throws {
    let unmarked = fixtureF()
    let unmarkedStore = store([unmarked.amazon, unmarked.savingsDebit, unmarked.cardCredit])

    let f = fixtureF()
    f.savingsDebit.transferGroupID = group
    f.savingsDebit.transferSourceRaw = TransferSource.manual.rawValue
    f.cardCredit.transferGroupID = group
    f.cardCredit.transferSourceRaw = TransferSource.manual.rawValue
    let markedStore = store([f.amazon, f.savingsDebit, f.cardCredit])

    let insights = try markedStore.insights(for: .month(year: 2025, month: 11))
    XCTAssertEqual(insights.debitMinor, 2_000_000)
    XCTAssertEqual(insights.creditMinor, 0)
    XCTAssertEqual(insights.netMinor, -2_000_000)
    XCTAssertEqual(insights.transactionCount, 1)
    XCTAssertEqual(insights.uncategorizedCount, 0)
    XCTAssertEqual(insights.needsReviewCount, 1, "a transfer still needs its review")

    let shoppingRow = try XCTUnwrap(
      try markedStore.budgetProgress(year: 2025, month: 11).first { $0.id == shopping })
    XCTAssertEqual(shoppingRow.spentMinor, 2_000_000)

    let november = try XCTUnwrap(
      try markedStore.trend(months: 1200).first { $0.id == Calendar.current.date(from: DateComponents(year: 2025, month: 11)) })
    XCTAssertEqual(november.debitMinor, 2_000_000)
    XCTAssertEqual(november.creditMinor, 0)

    let marked = try markedStore.accountSummaries(includeArchived: true)
    let unmarkedSummaries = try unmarkedStore.accountSummaries(includeArchived: true)
    XCTAssertEqual(marked.map(\.trackedBalanceMinor), unmarkedSummaries.map(\.trackedBalanceMinor))
    XCTAssertEqual(marked.first { $0.id == savings }?.trackedBalanceMinor, 8_000_000)
    XCTAssertEqual(marked.first { $0.id == card }?.trackedBalanceMinor, 0)
  }

  /// Amendment 3, rule U1 and U6. Exclusion reads only the group id, so the
  /// source value does not change a figure: a group id with an unrecognised
  /// source is a transfer, and a bare unrecognised source is spend.
  func testAnUnrecognizedSourceFollowsTheGroupID() throws {
    let withGroup = fixtureF()
    for row in [withGroup.savingsDebit, withGroup.cardCredit] {
      row.transferGroupID = group
      row.transferSourceRaw = "zzz"
    }
    let groupedInsights = try store([withGroup.amazon, withGroup.savingsDebit, withGroup.cardCredit])
      .insights(for: .month(year: 2025, month: 11))
    XCTAssertEqual(groupedInsights.debitMinor, 2_000_000)
    XCTAssertEqual(groupedInsights.creditMinor, 0)

    let withoutGroup = fixtureF()
    for row in [withoutGroup.savingsDebit, withoutGroup.cardCredit] {
      row.transferSourceRaw = "zzz"
    }
    let ungroupedInsights = try store([withoutGroup.amazon, withoutGroup.savingsDebit, withoutGroup.cardCredit])
      .insights(for: .month(year: 2025, month: 11))
    XCTAssertEqual(ungroupedInsights.debitMinor, 4_000_000)
    XCTAssertEqual(ungroupedInsights.creditMinor, 2_000_000)
  }
}
