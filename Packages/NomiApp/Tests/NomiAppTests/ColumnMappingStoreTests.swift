import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// Finding 5's app half: `ColumnMappingRecord` has been in the schema since U1
/// and nothing ever wrote to it, so `FileImportServiceImpl` ran on its
/// `InMemoryColumnMappingStore` default and every learned mapping died with the
/// process.
///
/// Two layers, tested separately on purpose. The encoding is pure and is where a
/// mistake would be permanent and silent — a `mappingJSON` written in a shape
/// the reader cannot parse looks exactly like "this app never remembers my
/// bank". The store itself needs a real `ModelContainer`.
final class ColumnMappingStoreTests: XCTestCase {

  // MARK: - Encoding

  func testAMappingSurvivesTheJSONRoundTrip() throws {
    let mapping = Self.hdfcMapping
    let json = try XCTUnwrap(ColumnMappingCoding.json(from: mapping))
    let saved = try XCTUnwrap(ColumnMappingCoding.saved(fromJSON: json, bankLabel: "HDFC"))

    XCTAssertEqual(saved.mapping, mapping)
    XCTAssertEqual(saved.bankLabel, "HDFC")
  }

  /// Every field, not just the ones a default `ColumnMapping` happens to
  /// exercise. `referenceColumn` is the optional one and the easiest to lose.
  func testTheOptionalReferenceColumnSurvivesBothWays() throws {
    for reference in [nil, 7] as [Int?] {
      let mapping = ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 2,
        referenceColumn: reference,
        directionStrategy: .signedAmount,
        dateFormat: "dd/MM/yyyy"
      )
      let json = try XCTUnwrap(ColumnMappingCoding.json(from: mapping))
      let saved = try XCTUnwrap(ColumnMappingCoding.saved(fromJSON: json, bankLabel: "X"))
      XCTAssertEqual(saved.mapping.referenceColumn, reference)
    }
  }

  /// Unreadable stored JSON reads as "nothing learned", not as a crash and not
  /// as a half-populated mapping. The import screen then falls back to
  /// `BankPresets` or asks — what it does for a format it has never seen.
  func testUnreadableJSONReadsAsNoMapping() {
    XCTAssertNil(ColumnMappingCoding.saved(fromJSON: "", bankLabel: "X"))
    XCTAssertNil(ColumnMappingCoding.saved(fromJSON: "{\"dateColumn\":0}", bankLabel: "X"))
    XCTAssertNil(ColumnMappingCoding.saved(fromJSON: "not json at all", bankLabel: "X"))
  }

  // MARK: - The store

  /// The acceptance criterion: written through one store instance, read back
  /// through another, on one container. Two instances because that is the shape
  /// of the bug — `InMemoryColumnMappingStore` passes a same-instance read and
  /// fails this.
  func testAMappingWrittenByOneInstanceIsReadByAnotherOnTheSameContainer() throws {
    let container = try Self.makeContainer()

    let writer = SwiftDataColumnMappingStore(container: container)
    writer.save(Self.hdfcMapping, signature: "sig-hdfc", bankLabel: "HDFC Bank")

    let reader = SwiftDataColumnMappingStore(container: container)
    let saved = try XCTUnwrap(reader.mapping(forSignature: "sig-hdfc"))

    XCTAssertEqual(saved.mapping, Self.hdfcMapping)
    XCTAssertEqual(saved.bankLabel, "HDFC Bank")
  }

  func testAnUnknownSignatureHasNoMapping() throws {
    let store = SwiftDataColumnMappingStore(container: try Self.makeContainer())
    XCTAssertNil(store.mapping(forSignature: "never-seen"))
  }

  /// Signatures do not bleed into each other. Cheap to assert and the predicate
  /// is the only thing standing between "your ICICI mapping" and "some mapping".
  func testMappingsAreKeyedBySignature() throws {
    let container = try Self.makeContainer()
    let store = SwiftDataColumnMappingStore(container: container)

    store.save(Self.hdfcMapping, signature: "sig-hdfc", bankLabel: "HDFC Bank")
    store.save(Self.iciciMapping, signature: "sig-icici", bankLabel: "ICICI Bank")

    XCTAssertEqual(store.mapping(forSignature: "sig-hdfc")?.mapping, Self.hdfcMapping)
    XCTAssertEqual(store.mapping(forSignature: "sig-icici")?.mapping, Self.iciciMapping)
  }

  /// `saveMapping` is called on *every* commit, so re-importing the same bank's
  /// statement each month must not leave a row per import. It is an upsert: the
  /// later value wins and there is still exactly one record.
  func testSavingTheSameSignatureTwiceUpdatesRatherThanDuplicates() throws {
    let container = try Self.makeContainer()
    let store = SwiftDataColumnMappingStore(container: container)

    store.save(Self.hdfcMapping, signature: "sig", bankLabel: "HDFC Bank")
    store.save(Self.iciciMapping, signature: "sig", bankLabel: "Corrected Label")

    let saved = try XCTUnwrap(store.mapping(forSignature: "sig"))
    XCTAssertEqual(saved.mapping, Self.iciciMapping)
    XCTAssertEqual(saved.bankLabel, "Corrected Label")

    let all = try ModelContext(container).fetch(FetchDescriptor<ColumnMappingRecord>())
    XCTAssertEqual(all.count, 1)
  }

  // MARK: - The refresh signal

  /// Finding 4's app half. `InsightsCache` cannot cross into `NomiUI`, so the
  /// composition root republishes its generation and `RootView` hands that to
  /// `DashboardView` and `ReportsScreen`.
  ///
  /// The screens are Morgan's and have their own test that two view values
  /// differing only in `refreshToken` compare as different. What is asserted
  /// here is the half that unit could not reach: that the number actually moves.
  @MainActor
  func testTheEnvironmentRepublishesTheCachesGeneration() throws {
    let environment = try Self.makeEnvironment()
    let before = environment.insightsGeneration
    XCTAssertEqual(before, environment.cache.generation)

    environment.cache.invalidate()

    XCTAssertEqual(environment.insightsGeneration, before + 1)
  }

  /// Every write invalidates, so the token has to keep moving rather than
  /// latching on the first one.
  @MainActor
  func testTheRepublishedGenerationKeepsMoving() throws {
    let environment = try Self.makeEnvironment()
    let before = environment.insightsGeneration

    environment.cache.invalidate()
    environment.cache.invalidate()
    environment.cache.invalidate()

    XCTAssertEqual(environment.insightsGeneration, before + 3)
  }

  // MARK: - The wiring, end to end

  /// The finding stated as the user's complaint: "I told it which column the
  /// date was in, and next time it asked me again."
  ///
  /// Two `AppEnvironment`s on one container stand in for two launches. Both go
  /// through the public `FileImportService` contract — `inspect`, then
  /// `saveMapping` with the preview's own signature — so this asserts the
  /// composition, not the store it happens to be built from. With the
  /// `InMemoryColumnMappingStore` default it fails on the last two lines.
  @MainActor
  func testAMappingLearnedInOneLaunchIsFoundInTheNext() async throws {
    let container = try Self.makeContainer()
    let url = try Self.writeStatement()
    defer { try? FileManager.default.removeItem(at: url) }

    let firstLaunch = try Self.makeEnvironment(container: container)
    let cold = try await firstLaunch.fileImportService.inspect(url)
    // Nothing learned and no preset for these headers, which is what makes the
    // assertion below mean something.
    XCTAssertNil(cold.detectedBankLabel)
    XCTAssertNil(cold.suggestedMapping)

    try firstLaunch.fileImportService.saveMapping(
      Self.hdfcMapping, signature: cold.formatSignature, bankLabel: "HDFC Bank")

    let secondLaunch = try Self.makeEnvironment(container: container)
    let warm = try await secondLaunch.fileImportService.inspect(url)

    XCTAssertEqual(warm.detectedBankLabel, "HDFC Bank")
    XCTAssertEqual(warm.suggestedMapping, Self.hdfcMapping)
  }

  // MARK: -

  private static let hdfcMapping = ColumnMapping(
    dateColumn: 0,
    descriptionColumn: 1,
    amountColumn: 3,
    referenceColumn: 2,
    directionStrategy: .signedAmount,
    dateFormat: "dd/MM/yy"
  )

  private static let iciciMapping = ColumnMapping(
    dateColumn: 1,
    descriptionColumn: 4,
    amountColumn: 5,
    referenceColumn: nil,
    directionStrategy: .signedAmount,
    dateFormat: "dd-MM-yyyy"
  )

  /// The app's own schema, in memory. Not `InMemoryModelContainer.shared`: that
  /// one is process-wide, so rows written by one test would be visible to the
  /// next and "an unknown signature has no mapping" would depend on run order.
  private static func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(
      schema: NomiModelContainer.schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: NomiModelContainer.schema, configurations: [configuration])
  }

  /// Every injectable default replaced. The real ones reach the Keychain, a
  /// socket, and `UNUserNotificationCenter`, and the last of those traps in a
  /// process with no bundle.
  @MainActor
  private static func makeEnvironment(
    container: ModelContainer? = nil
  ) throws -> AppEnvironment {
    AppEnvironment(
      container: try container ?? makeContainer(),
      preferences: InMemoryKeyValueStore(),
      credentials: MemoryCredentialStore(),
      mailFetcher: RecordingMailFetcher(uids: []),
      scheduler: SilentNotificationScheduler()
    )
  }
}

/// Four columns matching no `BankPresets` entry — those compare the whole header
/// list, so anything that is not exactly one of the five known layouts falls
/// through to the mapping store, which is the path under test.
extension ColumnMappingStoreTests {
  fileprivate static func writeStatement() throws -> URL {
    let csv = """
      Posting Date,Details,Ref,Amount
      01/08/26,UPI-SWIGGY,X1234,-450.00
      03/08/26,SALARY AUG,Y9876,120000.00
      """
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-mapping-\(UUID().uuidString).csv")
    try Data(csv.utf8).write(to: url)
    return url
  }
}

/// Records nothing and answers no. `AppEnvironment` only holds it; these tests
/// never reach a budget crossing.
private final class SilentNotificationScheduler: BudgetNotificationScheduling, @unchecked Sendable {
  @discardableResult
  func requestAuthorization() async throws -> Bool { false }
  func schedule(_ alert: BudgetAlert) async throws {}
}
