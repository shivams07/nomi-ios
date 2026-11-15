import Foundation
import NomiCore
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// I-10. `unassignedTransactions()` is every row with no account, newest first,
/// and it is read without the cache: a row bound to an account leaves the list
/// on the next read.
///
/// `FakeInsightsStore` gives the same answer on the same rows, because every
/// preview and UI-facing test reads it. The stack is held in a stored property
/// (see `InMemoryStack`).
@MainActor
final class UnassignedTransactionsTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    components.timeZone = calendar.timeZone
    return calendar.date(from: components)!
  }

  private func makeStore() throws -> (SwiftDataInsightsStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let store = SwiftDataInsightsStore(
      context: stack.context, cache: InsightsCache(), calendar: calendar,
      now: { [calendar] in
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
      })
    return (store, stack.context)
  }

  /// The done-when: three rows, one with no account, and exactly that one comes
  /// back.
  func testOnlyTheRowWithNoAccountComesBack() throws {
    let (store, context) = try makeStore()
    let account = Account(
      displayName: "HDFC", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank")
    context.insert(account)
    let bound = Transaction(date: date(2026, 11, 3), amountMinor: 100, accountID: account.id)
    let loose = Transaction(date: date(2026, 11, 2), amountMinor: 200)
    let alsoBound = Transaction(date: date(2026, 11, 1), amountMinor: 300, accountID: account.id)
    context.insert(bound)
    context.insert(loose)
    context.insert(alsoBound)
    try context.save()

    XCTAssertEqual(try store.unassignedTransactions().map(\.id), [loose.id])
  }

  /// Two unassigned rows come back newest first, whatever order they were
  /// inserted in.
  func testTwoUnassignedRowsComeBackNewestFirst() throws {
    let (store, context) = try makeStore()
    let older = Transaction(date: date(2026, 11, 2), amountMinor: 100)
    let newer = Transaction(date: date(2026, 11, 9), amountMinor: 200)
    context.insert(newer)
    context.insert(older)
    try context.save()

    XCTAssertEqual(try store.unassignedTransactions().map(\.id), [newer.id, older.id])
  }

  /// No cache. The first read puts a row in the list; a second row added after
  /// that must show up on the next read. A cached answer would still say one.
  func testTheListIsReadFreshAfterAnInsert() throws {
    let (store, context) = try makeStore()
    context.insert(Transaction(date: date(2026, 11, 3), amountMinor: 100))
    try context.save()
    XCTAssertEqual(try store.unassignedTransactions().count, 1)

    context.insert(Transaction(date: date(2026, 11, 4), amountMinor: 200))
    try context.save()

    XCTAssertEqual(
      try store.unassignedTransactions().count, 2, "a cached read would still say 1")
  }

  /// The fake and the store agree on the same rows, including the order.
  func testTheFakeGivesTheStoresAnswerOnTheSameRows() throws {
    let (store, context) = try makeStore()
    let account = Account(
      displayName: "ICICI", institution: "ICICI Bank", lastFour: "8890", kindRaw: "card")
    context.insert(account)
    let bound = Transaction(date: date(2026, 11, 5), amountMinor: 100, accountID: account.id)
    let loose = Transaction(date: date(2026, 11, 2), amountMinor: 200)
    let looseNewer = Transaction(date: date(2026, 11, 9), amountMinor: 300)
    context.insert(bound)
    context.insert(loose)
    context.insert(looseNewer)
    try context.save()

    let fake = FakeInsightsStore(
      transactions: [bound, loose, looseNewer], categories: [], accounts: [], budgets: [])

    let fromStore = try store.unassignedTransactions().map(\.id)
    let fromFake = try fake.unassignedTransactions().map(\.id)

    XCTAssertEqual(fromStore, [looseNewer.id, loose.id])
    XCTAssertEqual(fromFake, fromStore)
  }
}
