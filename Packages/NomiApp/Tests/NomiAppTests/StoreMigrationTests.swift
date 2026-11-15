import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// Data safety of `NomiSchemaV1` (R7, I-6). These tests put rows in a store
/// with today's unversioned construction, then open that file under V1, and
/// check every row and amount is still there.
///
/// XCTest, not swift-testing: a `ModelContainer` built under swift-testing
/// traps in this package (see `InMemoryModelContainer`'s note). Every test
/// keeps its container alive to the end with `withExtendedLifetime`, because a
/// `ModelContext` does not hold its container and the trap is a dropped
/// container (see `reference_swiftdata_container_lifetime_trap`).
final class StoreMigrationTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private var storeURL: URL {
    directory.appendingPathComponent("default.store")
  }

  /// Today's construction, copied from `NomiModelContainer` before R7: a bare
  /// `Schema` list, no version, no migration plan. This is the store every
  /// existing user already has on disk.
  private func writeUnversionedStore() throws {
    let url = storeURL
    let schema = Schema([
      Transaction.self,
      NomiCore.Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    let context = ModelContext(container)
    seedRows(into: context)
    try context.save()
    withExtendedLifetime(container) {}
  }

  /// The same rows as `writeUnversionedStore`, through the V1 path.
  private func writeV1Store() throws {
    let container = try NomiModelContainer.makeLocal(at: storeURL)
    let context = ModelContext(container)
    seedRows(into: context)
    try context.save()
    withExtendedLifetime(container) {}
  }

  private func seedRows(into context: ModelContext) {
    context.insert(Transaction(amountMinor: 12345))
    context.insert(Transaction(amountMinor: 500))
    context.insert(Account(displayName: "Savings"))
    context.insert(NomiCore.Category(name: "Food"))
    context.insert(Rule(pattern: "SWIGGY*", categoryID: UUID()))
  }

  /// Counts and the two amounts, read back through a container at `storeURL`.
  private func assertRowsIntact(in container: ModelContainer, file: StaticString = #filePath, line: UInt = #line) throws {
    let context = ModelContext(container)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2, file: file, line: line)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Account>()), 1, file: file, line: line)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<NomiCore.Category>()), 1, file: file, line: line)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Rule>()), 1, file: file, line: line)
    let amounts = try context.fetch(FetchDescriptor<Transaction>()).map(\.amountMinor).sorted()
    XCTAssertEqual(amounts, [500, 12345], file: file, line: line)
  }

  /// The data-safety proof: a store written unversioned opens under V1 with
  /// every row and both amounts intact.
  func testAStoreWrittenByTheUnversionedSchemaOpensUnderV1WithItsRows() throws {
    try writeUnversionedStore()

    let container = try NomiModelContainer.makeLocal(at: storeURL)
    try assertRowsIntact(in: container)
    withExtendedLifetime(container) {}
  }

  /// Once a store is V1, reopening it under V1 changes nothing.
  func testReopeningAV1StoreUnderV1IsANoOp() throws {
    try writeV1Store()

    let first = try NomiModelContainer.makeLocal(at: storeURL)
    try assertRowsIntact(in: first)
    withExtendedLifetime(first) {}
  }

  /// One list for the app and for previews. A model added to one and not the
  /// other would open in the app and trap in a preview.
  func testV1ListsExactlyTheEightAppModels() {
    let expected: Set<String> = [
      "Transaction", "Category", "Budget", "BudgetAlertLog",
      "Rule", "Account", "AccountBinding", "ColumnMappingRecord",
    ]
    XCTAssertEqual(Set(NomiModelContainer.schema.entities.map(\.name)), expected)
    XCTAssertEqual(Set(InMemoryModelContainer.shared.schema.entities.map(\.name)), expected)
    XCTAssertEqual(NomiSchemaV1.models.count, 8, "NomiSchemaV1.models is the one list both containers read")
  }
}
