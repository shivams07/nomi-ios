import Foundation
import NomiCore
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// W2-2. Search has to find a row the ledger window cannot reach, so every
/// assertion here is against a **real container** — the whole unit is one
/// `FetchDescriptor`, and a fake would be testing the fixture.
///
/// That matters more than usual here. `#Predicate` compiles far more than
/// SwiftData can carry into a store query; an unsupported expression is a
/// runtime throw at `fetch`, not a build error. A test over an in-memory array
/// would be green against a predicate the app cannot execute.
///
/// A `ModelContainer` under `swift test` is fine in XCTest and traps under
/// swift-testing — see `InMemoryModelContainer` — which is why this is XCTest,
/// like `AccountStoreTests` next to it.
@MainActor
final class TransactionSearchTests: XCTestCase {

  /// The done-when, in one test: 300 rows, and "swiggy" reaches each of the
  /// four searchable fields exactly once.
  ///
  /// The four are not interchangeable and none of them is redundant.
  /// `descriptionText` is the bank's raw narration, `merchantName` is what the
  /// extractor made of it, `counterpartyVPA` is the UPI handle, and `note` is
  /// what the user typed. Dropping any one clause from the predicate leaves
  /// three matches here instead of four, and this is the only place that would
  /// notice.
  ///
  /// The 298 filler rows are not padding. They are what makes the match count
  /// meaningful: the predicate runs in SQLite over a table where the needle is
  /// rare, which is the shape the screen has, and a `contains` that had
  /// accidentally become "matches everything" would return 300 here rather
  /// than passing.
  func testSearchMatchesAcrossAllFourFieldsAcrossTheWholeLedger() throws {
    let context = try makeContext()

    let byDescription = Transaction(
      date: day(1), descriptionText: "UPI/SWIGGY ORDER/123456", amountMinor: 45_000)
    let byMerchant = Transaction(
      date: day(2), descriptionText: "POS PURCHASE 4471", merchantName: "Swiggy Instamart",
      amountMinor: 32_000)
    let byVPA = Transaction(
      date: day(3), descriptionText: "UPI PAYMENT", counterpartyVPA: "swiggy@axisbank",
      amountMinor: 18_000)
    let byNote = Transaction(
      date: day(4), descriptionText: "CARD PAYMENT", amountMinor: 12_000,
      note: "dinner, swiggy refund pending")

    for row in [byDescription, byMerchant, byVPA, byNote] { context.insert(row) }
    insertFiller(298, into: context, from: 100)
    try context.save()

    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Transaction>()), 300, "300 rows, as specified")

    let results = try SwiftDataTransactionSearch(context: context).search("swiggy", limit: 50)

    XCTAssertEqual(
      Set(results.map(\.id)),
      Set([byDescription.id, byMerchant.id, byVPA.id, byNote.id]),
      "one match per searchable field, and nothing else in 300 rows")
  }

  /// The done-when's second half. `limit` is applied by the store, after the
  /// sort — not by the caller after the fact — so the two that come back are
  /// the two *newest* matches and not two arbitrary ones.
  ///
  /// Both directions are pinned. The second assertion raises the limit and gets
  /// all three back, so the first one dropping `oldest` is the cap doing it and
  /// not the predicate having quietly missed a row — which is the way a
  /// limit test passes while meaning nothing.
  ///
  /// The 297 filler rows are all *newer* than every match, so a `fetchLimit`
  /// applied before the predicate rather than after would come back with
  /// filler and no matches at all.
  func testLimitReturnsTheNewestMatchesNotAnyTwo() throws {
    let context = try makeContext()

    let oldest = Transaction(date: day(1), descriptionText: "SWIGGY SWIGGY", amountMinor: 10_000)
    let middle = Transaction(date: day(5), descriptionText: "UPI/SWIGGY/2", amountMinor: 20_000)
    let newest = Transaction(date: day(9), descriptionText: "UPI/SWIGGY/3", amountMinor: 30_000)
    for row in [oldest, middle, newest] { context.insert(row) }
    insertFiller(297, into: context, from: 100)
    try context.save()

    let search = SwiftDataTransactionSearch(context: context)

    XCTAssertEqual(
      try search.search("swiggy", limit: 2).map(\.id), [newest.id, middle.id],
      "newest first, capped at two")
    XCTAssertEqual(
      try search.search("swiggy", limit: 50).map(\.id), [newest.id, middle.id, oldest.id],
      "and the cap is the only thing that dropped the third")
  }

  /// `localizedStandardContains` is case- and diacritic-insensitive, which is
  /// the whole reason the predicate uses it rather than `contains`. The user
  /// types "swiggy"; the bank sent "SWIGGY".
  func testMatchingIsCaseAndDiacriticInsensitive() throws {
    let context = try makeContext()
    let shouty = Transaction(date: day(1), descriptionText: "UPI/SWIGGY/1", amountMinor: 1_000)
    let accented = Transaction(date: day(2), descriptionText: "CAFÉ COFFEE DAY", amountMinor: 2_000)
    context.insert(shouty)
    context.insert(accented)
    try context.save()

    let search = SwiftDataTransactionSearch(context: context)

    XCTAssertEqual(try search.search("swiggy", limit: 10).map(\.id), [shouty.id])
    XCTAssertEqual(try search.search("SwIgGy", limit: 10).map(\.id), [shouty.id])
    XCTAssertEqual(try search.search("cafe", limit: 10).map(\.id), [accented.id])
  }

  /// A partial merchant name is what a user actually types. If this ever fails
  /// the predicate has become an equality test.
  func testAPartialTokenMatches() throws {
    let context = try makeContext()
    let row = Transaction(
      date: day(1), descriptionText: "POS", merchantName: "Swiggy Instamart",
      amountMinor: 1_000)
    context.insert(row)
    try context.save()

    XCTAssertEqual(
      try SwiftDataTransactionSearch(context: context).search("instamart", limit: 10).map(\.id),
      [row.id])
  }

  /// "Contains the empty string" is true of every row, so a blank query would
  /// otherwise return the whole ledger truncated to `limit`: a plausible-looking
  /// list of unrelated rows, arriving the instant the user focuses the field and
  /// before they have typed anything.
  ///
  /// Whitespace counts as blank. A field with one space in it is not a search.
  func testABlankOrWhitespaceQueryReturnsNothingRatherThanEverything() throws {
    let context = try makeContext()
    insertFiller(20, into: context, from: 100)
    try context.save()

    let search = SwiftDataTransactionSearch(context: context)

    XCTAssertTrue(try search.search("", limit: 10).isEmpty)
    XCTAssertTrue(try search.search("   ", limit: 10).isEmpty)
    XCTAssertTrue(try search.search("\n\t", limit: 10).isEmpty)
  }

  /// A non-positive limit is a caller bug, and the honest answer is nothing —
  /// not an unbounded fetch. `FetchDescriptor.fetchLimit = 0` means *no limit*
  /// to SwiftData, so without the guard `limit: 0` is the whole-ledger read
  /// this contract exists to avoid.
  func testANonPositiveLimitReturnsNothingRatherThanTheWholeLedger() throws {
    let context = try makeContext()
    insertFiller(20, into: context, from: 100)
    context.insert(Transaction(date: day(1), descriptionText: "SWIGGY", amountMinor: 1_000))
    try context.save()

    let search = SwiftDataTransactionSearch(context: context)

    XCTAssertTrue(try search.search("swiggy", limit: 0).isEmpty)
    XCTAssertTrue(try search.search("swiggy", limit: -1).isEmpty)
  }

  /// The query is trimmed before it is used, so a trailing space from the
  /// keyboard does not silently stop matching.
  func testTheQueryIsTrimmedBeforeMatching() throws {
    let context = try makeContext()
    let row = Transaction(date: day(1), descriptionText: "UPI/SWIGGY/1", amountMinor: 1_000)
    context.insert(row)
    try context.save()

    XCTAssertEqual(
      try SwiftDataTransactionSearch(context: context).search("  swiggy ", limit: 10).map(\.id),
      [row.id])
  }

  /// The three optional columns are written `($0.x ?? "")`, and a row where all
  /// three are `nil` is the common case — every imported statement row. If the
  /// coalesce were wrong, or the predicate could not carry it, this either
  /// throws at `fetch` or returns nothing.
  func testRowsWithEveryOptionalFieldNilAreSearchableByDescription() throws {
    let context = try makeContext()
    let bare = Transaction(date: day(1), descriptionText: "NEFT SWIGGY LTD", amountMinor: 1_000)
    XCTAssertNil(bare.merchantName)
    XCTAssertNil(bare.counterpartyVPA)
    XCTAssertNil(bare.note)
    context.insert(bare)
    try context.save()

    XCTAssertEqual(
      try SwiftDataTransactionSearch(context: context).search("swiggy", limit: 10).map(\.id),
      [bare.id])
  }

  // MARK: - The fake must agree

  /// The preview stack and production must not disagree about which fields are
  /// searchable, or the Ledger preview demonstrates results the app cannot
  /// produce. Same rows, same query, same answer.
  func testBothSearchesAgreeOnWhichRowsMatchAndInWhatOrder() throws {
    let context = try makeContext()

    let rows = [
      Transaction(date: day(1), descriptionText: "UPI/SWIGGY ORDER", amountMinor: 45_000),
      Transaction(
        date: day(2), descriptionText: "POS PURCHASE", merchantName: "Swiggy Instamart",
        amountMinor: 32_000),
      Transaction(
        date: day(3), descriptionText: "UPI PAYMENT", counterpartyVPA: "swiggy@axisbank",
        amountMinor: 18_000),
      Transaction(
        date: day(4), descriptionText: "CARD PAYMENT", amountMinor: 12_000, note: "swiggy refund"),
      Transaction(date: day(5), descriptionText: "AMAZON", amountMinor: 9_000),
    ]
    for row in rows { context.insert(row) }
    try context.save()

    let real = try SwiftDataTransactionSearch(context: context).search("swiggy", limit: 3)
    // The fake is handed copies, not the inserted instances: a `@Model` belongs
    // to its context, and the fake is meant to hold plain rows.
    let fake = try FakeTransactionSearch(
      transactions: rows.map {
        Transaction(
          id: $0.id, date: $0.date, descriptionText: $0.descriptionText,
          merchantName: $0.merchantName, counterpartyVPA: $0.counterpartyVPA,
          amountMinor: $0.amountMinor, note: $0.note)
      }
    ).search("swiggy", limit: 3)

    XCTAssertEqual(real.map(\.id), fake.map(\.id), "the two searches disagree")
    XCTAssertEqual(real.count, 3, "and both respected the limit")
  }

  func testTheFakeAlsoRefusesABlankQueryAndANonPositiveLimit() throws {
    let fake = FakeTransactionSearch(
      transactions: [Transaction(date: day(1), descriptionText: "SWIGGY", amountMinor: 1_000)])

    XCTAssertTrue(try fake.search("", limit: 10).isEmpty)
    XCTAssertTrue(try fake.search("  ", limit: 10).isEmpty)
    XCTAssertTrue(try fake.search("swiggy", limit: 0).isEmpty)
    XCTAssertEqual(try fake.search("swiggy", limit: 10).count, 1)
  }

  // MARK: -

  /// A fresh container per test, and deliberately not
  /// `InMemoryModelContainer.shared`: these tests count rows.
  private func makeContext() throws -> ModelContext {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    return container.mainContext
  }

  /// Rows that cannot match "swiggy" on any of the four fields, one per day so
  /// nothing ties on date. Called with `from: 100`, so the filler is *newer*
  /// than every match — which is the harder direction: a predicate that matched
  /// too much, or a `fetchLimit` applied before the sort, fills the answer with
  /// filler and the match assertions fail rather than passing by luck.
  private func insertFiller(_ count: Int, into context: ModelContext, from start: Int) {
    for offset in 0..<count {
      context.insert(
        Transaction(
          date: day(start + offset),
          descriptionText: "NEFT TRANSFER \(offset)",
          merchantName: "Merchant \(offset)",
          counterpartyVPA: "payee\(offset)@okhdfcbank",
          amountMinor: 1_000 + offset,
          note: "filler \(offset)"
        ))
    }
  }

  /// One day per index, forward from a fixed instant, so `day(1)` is older than
  /// `day(9)` and every date is distinct. A fixed epoch and not `Date()`: CI
  /// runs UTC and a phone in India does not, and nothing here should depend on
  /// which.
  private func day(_ index: Int) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(Double(index) * 86_400)
  }
}
