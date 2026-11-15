import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// B2, I-11. The two hints the entry sheet pre-fills from: the account the user last used,
/// and the categories past rows with the same description were filed under.
///
/// XCTest on an `InMemoryStack` held in a property for the life of the test.
@MainActor
final class EntryHintsTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india

  /// A clock the store reads for `createdAt`, so "most recently created" is a set order.
  private final class EntryClock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private func day(_ d: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 12))!
  }

  private struct Fixture {
    let store: SwiftDataTransactionStore
    let context: ModelContext
    let clock: EntryClock
  }

  private func makeFixture() throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let clock = EntryClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = SwiftDataTransactionStore(
      context: stack.context,
      coordinator: WriteCoordinator(cache: InsightsCache()),
      calendar: calendar,
      now: { clock.now }
    )
    return Fixture(store: store, context: stack.context, clock: clock)
  }

  /// A past row written straight to the context. `normalizedDescription` is what the
  /// suggestion matches on, so the fixture sets it the way the pipeline does.
  private func insertRow(
    _ context: ModelContext,
    description: String,
    date: Date,
    createdAt: Date,
    categoryID: UUID? = nil,
    accountID: UUID? = nil,
    source: IngestSource = .manual,
    transferGroupID: UUID? = nil
  ) throws {
    let row = Transaction(
      date: date,
      descriptionText: description,
      normalizedDescription: normalizeDescription(description),
      amountMinor: 50_000,
      directionRaw: Direction.debit.rawValue,
      categoryID: categoryID,
      categorySourceRaw: categoryID == nil ? CategorySource.none.rawValue : CategorySource.manual.rawValue,
      accountID: accountID,
      sourceRaw: source.rawValue,
      dedupeKey: UUID().uuidString,
      createdAt: createdAt,
      updatedAt: createdAt,
      transferGroupID: transferGroupID,
      transferSourceRaw: transferGroupID == nil ? nil : TransferSource.manual.rawValue
    )
    context.insert(row)
    try context.save()
  }

  private func insertCategory(_ context: ModelContext, id: UUID, name: String) throws {
    context.insert(Category(id: id, name: name))
    try context.save()
  }

  // MARK: - lastUsedAccountID

  func testThereIsNoLastUsedAccountWithoutAManualRowThatHasOne() throws {
    let f = try makeFixture()
    XCTAssertNil(f.store.lastUsedAccountID())

    _ = try f.store.add(ManualTransactionDraft(date: day(10), amountMinor: 500, descriptionText: "CHAI"))
    XCTAssertNil(f.store.lastUsedAccountID(), "a manual row with no account counts as a last-used account")
  }

  /// The newest manual row that has an account wins: the account of the last one created, not
  /// the one with the latest transaction date.
  func testTheLastUsedAccountIsTheNewestManualRowWithOne() throws {
    let f = try makeFixture()
    let first = UUID()
    let second = UUID()

    _ = try f.store.add(
      ManualTransactionDraft(date: day(20), amountMinor: 500, descriptionText: "CHAI", accountID: first))
    f.clock.now = f.clock.now.addingTimeInterval(60)
    _ = try f.store.add(
      ManualTransactionDraft(date: day(1), amountMinor: 600, descriptionText: "CHAI", accountID: second))
    f.clock.now = f.clock.now.addingTimeInterval(60)
    _ = try f.store.add(ManualTransactionDraft(date: day(30), amountMinor: 700, descriptionText: "CHAI"))

    XCTAssertEqual(f.store.lastUsedAccountID(), second)
  }

  /// Only manual rows count. A mail or file row with an account says nothing about what the user
  /// last chose on this screen, even when it is newer.
  func testLastUsedAccountIgnoresFileAndEmailRows() throws {
    let f = try makeFixture()
    let manualAccount = UUID()
    let mailAccount = UUID()
    let fileAccount = UUID()
    let base = f.clock.now

    try insertRow(
      f.context, description: "CHAI", date: day(10), createdAt: base,
      accountID: manualAccount, source: .manual)
    try insertRow(
      f.context, description: "HDFC ALERT", date: day(11), createdAt: base.addingTimeInterval(60),
      accountID: mailAccount, source: .email)
    try insertRow(
      f.context, description: "STATEMENT", date: day(12), createdAt: base.addingTimeInterval(120),
      accountID: fileAccount, source: .file)

    XCTAssertEqual(f.store.lastUsedAccountID(), manualAccount)
  }

  // MARK: - suggestedCategories

  /// Three rows under A, two under B (newest day 10), two under C (newest day 5).
  /// Count first: A (3). Then B and C tie on count, and B is newer. So [A, B, C].
  func testSuggestionsOrderByCountThenRecencyAndRespectTheLimit() throws {
    let f = try makeFixture()
    let a = UUID()
    let b = UUID()
    let c = UUID()
    try insertCategory(f.context, id: a, name: "Food")
    try insertCategory(f.context, id: b, name: "Travel")
    try insertCategory(f.context, id: c, name: "Shopping")
    let base = f.clock.now

    for d in [1, 2, 3] {
      try insertRow(f.context, description: "SWIGGY ORDER", date: day(d), createdAt: base, categoryID: a)
    }
    for d in [9, 10] {
      try insertRow(f.context, description: "SWIGGY ORDER", date: day(d), createdAt: base, categoryID: b)
    }
    for d in [4, 5] {
      try insertRow(f.context, description: "SWIGGY ORDER", date: day(d), createdAt: base, categoryID: c)
    }

    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "swiggy", limit: 5), [a, b, c])
    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "swiggy", limit: 2), [a, b])
    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "swiggy", limit: 1), [a])
    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "swiggy", limit: 0), [])
  }

  /// The text is normalised the way the rows are: upper-cased, digits stripped, whitespace collapsed.
  /// So a lower-case query with a number in it still finds the row.
  func testTheQueryIsNormalisedBeforeItMatches() throws {
    let f = try makeFixture()
    let a = UUID()
    try insertCategory(f.context, id: a, name: "Food")
    try insertRow(f.context, description: "SWIGGY ORDER", date: day(1), createdAt: f.clock.now, categoryID: a)

    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "  swiggy 4411 ", limit: 5), [a])
  }

  /// A query that normalises to fewer than two characters suggests nothing, whatever the rows hold.
  func testATextShorterThanTwoCharactersSuggestsNothing() throws {
    let f = try makeFixture()
    let a = UUID()
    try insertCategory(f.context, id: a, name: "Food")
    try insertRow(f.context, description: "A STALL", date: day(1), createdAt: f.clock.now, categoryID: a)

    for text in ["a", " a ", "", "1", "7 "] {
      XCTAssertEqual(try f.store.suggestedCategories(forDescription: text, limit: 5), [], "text \"\(text)\"")
    }
  }

  /// Transfer legs, uncategorised rows and rows whose category has been deleted do not suggest.
  func testSuggestionsSkipTransfersUncategorisedRowsAndDeletedCategories() throws {
    let f = try makeFixture()
    let transferCategory = UUID()
    let kept = UUID()
    let deleted = UUID()
    try insertCategory(f.context, id: transferCategory, name: "Transfers")
    try insertCategory(f.context, id: kept, name: "Food")
    let base = f.clock.now

    try insertRow(
      f.context, description: "SWIGGY ORDER", date: day(1), createdAt: base,
      categoryID: transferCategory, transferGroupID: UUID())
    try insertRow(f.context, description: "SWIGGY ORDER", date: day(2), createdAt: base, categoryID: nil)
    try insertRow(f.context, description: "SWIGGY ORDER", date: day(3), createdAt: base, categoryID: deleted)
    try insertRow(f.context, description: "SWIGGY ORDER", date: day(4), createdAt: base, categoryID: kept)

    XCTAssertEqual(try f.store.suggestedCategories(forDescription: "swiggy", limit: 5), [kept])
  }
}
