import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp
@testable import NomiUI

/// WR-3b. Home's uncategorized count and the Ledger's Uncategorized chip must
/// list the same rows (DEC-05). Both are checked on one set of fixtures, each
/// row built once as a `Transaction` and once as the aggregator's value row:
///
/// - Home's count: `InsightsAggregator.insights(...).uncategorizedCount`.
/// - The SwiftData path: `LedgerFilterPredicate.matches` over the fetched
///   `Transaction`s, the same in-memory check the `@Query` result goes through.
/// - The in-memory path: `LedgerFiltering.apply` over the same `Transaction`s,
///   through the `LedgerRow` protocol the list draws from.
///
/// `NomiApp.LedgerRow` is qualified throughout: `NomiUI` has a `LedgerRow`
/// protocol of the same name, visible here under `@testable import`.
@MainActor
final class UncategorizedCountParityTests: XCTestCase {

  /// Owns each test's container for the life of the test. See `InMemoryStack`.
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  /// One fixture per pair state, each with no category, plus a categorized
  /// control of each kind so a chip that lists categorized rows also fails.
  /// `expectedListed` names the rows the chip and Home's count must both take.
  private struct Fixture {
    let label: String
    let groupID: UUID?
    let sourceRaw: String?
    let categoryID: UUID?
  }

  private func fixtures() -> [Fixture] {
    let group = UUID()
    return [
      Fixture(label: "unmarked", groupID: nil, sourceRaw: nil, categoryID: nil),
      Fixture(label: "auto", groupID: group, sourceRaw: "auto", categoryID: nil),
      Fixture(label: "manual", groupID: group, sourceRaw: "manual", categoryID: nil),
      Fixture(label: "rejected", groupID: nil, sourceRaw: "rejected", categoryID: nil),
      Fixture(label: "unrecognized with group", groupID: UUID(), sourceRaw: "zzz", categoryID: nil),
      Fixture(label: "unrecognized without group", groupID: nil, sourceRaw: "zzz", categoryID: nil),
      Fixture(label: "categorized", groupID: nil, sourceRaw: nil, categoryID: UUID()),
      Fixture(label: "categorized auto", groupID: UUID(), sourceRaw: "auto", categoryID: UUID()),
    ]
  }

  /// Rows the rule lists: no category and no group id.
  private let expectedListed: Set<String> = ["unmarked", "rejected", "unrecognized without group"]

  func testHomeCountAndBothChipPathsListTheSameRows() throws {
    let context = try makeContext()
    let fixtures = fixtures()
    let transactions = fixtures.map { fixture -> Transaction in
      let transaction = Transaction(
        date: date(2026, 10, 12),
        categoryID: fixture.categoryID,
        transferGroupID: fixture.groupID,
        transferSourceRaw: fixture.sourceRaw
      )
      context.insert(transaction)
      return transaction
    }
    try context.save()
    let labelByID = Dictionary(uniqueKeysWithValues: zip(transactions.map(\.id), fixtures.map(\.label)))

    // SwiftData path: the `@Query` result, filtered by the chip's own check.
    let filter = TransactionFilter(uncategorizedOnly: true)
    let swiftDataListed = Set(
      transactions
        .filter { LedgerFilterPredicate.matches($0, filter: filter, within: nil) }
        .compactMap { labelByID[$0.id] })

    // In-memory path: the protocol the list draws from.
    let inMemoryListed = Set(
      LedgerFiltering.apply(transactions, selection: .uncategorized)
        .compactMap { labelByID[$0.id] })

    // Home's count, over the value rows the aggregator reads.
    let appRows = transactions.map { transaction in
      NomiApp.LedgerRow(
        id: transaction.id,
        date: transaction.date,
        amountMinor: transaction.amountMinor,
        directionRaw: transaction.directionRaw,
        categoryID: transaction.categoryID,
        accountID: nil,
        normalizedDescription: "",
        merchantName: nil,
        descriptionText: "",
        needsReview: false,
        currencyCode: "INR",
        isTransfer: transaction.isTransfer
      )
    }
    let homeCount = InsightsAggregator.insights(
      period: .month(year: 2026, month: 10),
      rows: appRows,
      categories: [:],
      priorRows: nil,
      calendar: calendar
    ).uncategorizedCount

    XCTAssertEqual(swiftDataListed, expectedListed)
    XCTAssertEqual(inMemoryListed, expectedListed)
    XCTAssertEqual(homeCount, expectedListed.count)
    XCTAssertEqual(homeCount, swiftDataListed.count)
    XCTAssertEqual(homeCount, inMemoryListed.count)
  }

  // MARK: - Helpers

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    components.timeZone = calendar.timeZone
    return calendar.date(from: components)!
  }

  private func makeContext() throws -> ModelContext {
    let stack = try InMemoryStack(schema: Schema([Transaction.self]))
    stacks.append(stack)
    return stack.context
  }
}
