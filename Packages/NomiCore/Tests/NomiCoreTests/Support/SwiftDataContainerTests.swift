import Foundation
import SwiftData
import XCTest

@testable import NomiCore

/// The tests `InMemoryModelContainer`'s old note said could not exist: a
/// `ModelContainer` over the whole schema, a `@Model` inserted, saved and
/// fetched back, and a `#Predicate` fetch over the widest model in the repo.
///
/// **XCTest, and it has to stay XCTest — including for anything added here
/// later.** Every other test in this package is swift-testing, so this file is
/// the odd one out and looks like an oversight. It is not. Under the
/// swift-testing runner every test below traps on the first line that
/// constructs a container: `SwiftData/DataStoreCoreData.swift:32: Fatal error:
/// Unable to determine Bundle Name`, and `swift test` exits on signal 5 —
/// taking the rest of the package's tests with it. The rewritten note in
/// `NomiCore/Support/InMemoryModelContainer.swift` has the measurements.
final class SwiftDataContainerTests: XCTestCase {

  /// A fresh container per test, never `InMemoryModelContainer.shared`: that
  /// one is process-wide, so rows written by one test would be visible to the
  /// next and every count assertion here would depend on run order.
  private static func makeContainer() throws -> ModelContainer {
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
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  /// The bundle-name trap fires on store load, which is here — before any
  /// `@Model` instance exists. This one line is the whole boundary.
  func testAContainerOverTheWholeSchemaLoads() throws {
    _ = try Self.makeContainer()
  }

  func testAModelIsInsertedSavedAndFetchedBack() throws {
    let container = try Self.makeContainer()
    let context = ModelContext(container)
    let id = UUID()

    context.insert(Rule(id: id, pattern: "SWIGGY*", categoryID: UUID(), priority: 3))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Rule>())
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched.first?.id, id)
    XCTAssertEqual(fetched.first?.pattern, "SWIGGY*")
  }

  /// `Transaction` rather than `Rule`, because it is the wide one — optionals
  /// and a `[SourceRef]` stored as a `Codable` array — and a `#Predicate`,
  /// which is compiled against the store rather than against the type.
  func testAPredicateFetchOverTheWideModelWorks() throws {
    let container = try Self.makeContainer()
    let context = ModelContext(container)
    let captured = Date(timeIntervalSince1970: 1_756_000_000)

    context.insert(
      Transaction(
        descriptionText: "UPI/P2M/412345678901/SWIGGY",
        amountMinor: 45_900,
        directionRaw: Direction.debit.rawValue,
        sourceRefs: [SourceRef(source: .email, externalID: "uid-1", capturedAt: captured)],
        dedupeKey: "k1"
      )
    )
    context.insert(
      Transaction(amountMinor: 100, directionRaw: Direction.credit.rawValue, dedupeKey: "k2"))
    try context.save()

    let debit = Direction.debit.rawValue
    let matches = try context.fetch(
      FetchDescriptor<Transaction>(predicate: #Predicate { $0.directionRaw == debit })
    )

    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches.first?.amountMinor, 45_900)
    XCTAssertEqual(matches.first?.sourceRefs.first?.externalID, "uid-1")
  }

  /// `InMemoryModelContainer.shared` itself, which has never had a test and is
  /// a `try!` — so a schema that fails to load is a crash in every preview and
  /// in this suite rather than a failure anywhere readable.
  ///
  /// Keyed on its own `id` and asserting nothing about counts, because this
  /// container is shared with whatever else in the process touches it.
  func testTheSharedContainerLoadsAndRoundTripsARow() throws {
    let context = ModelContext(InMemoryModelContainer.shared)
    let id = UUID()

    context.insert(Rule(id: id, pattern: "SHARED*", categoryID: UUID()))
    try context.save()

    let found = try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate { $0.id == id }))
    XCTAssertEqual(found.map(\.pattern), ["SHARED*"])
  }
}
