import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// B4 (I-12): `FileImportService.dryRun` counts what `commit` would import and
/// writes nothing. The first group runs on fixture CSVs with a stub lookup. The
/// last group runs the real pipeline over a real `SwiftDataPipelineStore`, so
/// "already in Nomi" is read from rows that commit wrote.
///
/// **XCTest, and it has to stay XCTest**, as `SwiftDataPipelineStoreTests` does.
/// Every container the SwiftData cases build is kept in a stored property of the
/// test case: a container the test lets go of traps mid-test.
final class ImportDryRunTests: XCTestCase {
  /// Columns 0 to 3 as Date, Narration, Amount, Reference. Signed amounts,
  /// dd/MM/yyyy. The reference is the externalID, so the expected IDs are known.
  private let withReference = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: 3,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )

  /// Columns 0 to 2 as Date, Narration, Amount. No reference, so the externalID
  /// is the row's content digest and its index among identical rows (L10).
  private let withoutReference = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )

  // MARK: - Doubles

  /// The IDs already stored under `.file`, as the store would report them.
  private struct StubLookup: ImportedRowLookup {
    let ids: Set<String>

    func externalIDs(source: IngestSource) async throws -> Set<String> {
      source == .file ? ids : []
    }
  }

  private struct FailingLookup: ImportedRowLookup {
    struct LookupFailed: Error {}

    func externalIDs(source: IngestSource) async throws -> Set<String> {
      throw LookupFailed()
    }
  }

  /// Reports every draft as created, so the commit's count is checkable against
  /// the dry run. A dry run must leave both counters at zero.
  private actor RecordingIngester: DraftIngesting {
    private(set) var batchCount = 0
    private(set) var draftCount = 0

    func ingest(_ batch: [TransactionDraft]) async throws -> IngestBatchResult {
      batchCount += 1
      draftCount += batch.count
      return IngestBatchResult(created: batch.count, merged: 0, flagged: 0)
    }
  }

  // MARK: - Fixtures

  /// Builds a file's bytes from its lines. `eol` is the line ending, and `bom`
  /// prefixes the UTF-8 byte-order mark Excel writes.
  private static func csv(_ lines: [String], eol: String = "\n", bom: Bool = false) -> Data {
    var data = bom ? Data([0xEF, 0xBB, 0xBF]) : Data()
    data.append(Data((lines.joined(separator: eol) + eol).utf8))
    return data
  }

  /// Writes `bytes` to a fresh temporary file. The caller removes it.
  private func write(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-dryrun-\(UUID().uuidString).csv")
    try bytes.write(to: url)
    return url
  }

  // MARK: - Counts

  /// Five data rows: two new, two already stored, and one with no amount. The
  /// expected counts are 2 / 2 / 1.
  func testCountsNewAlreadyAndUnreadable() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,OLD ONE,10.00,REF3",
      "05/11/2026,OLD TWO,20.00,REF4",
      "06/11/2026,FEE,,REF5",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(
      pipeline: RecordingIngester(), lookup: StubLookup(ids: ["REF3", "REF4"]))

    let dry = try await service.dryRun(url, mapping: withReference)

    XCTAssertEqual(dry.newCount, 2)
    XCTAssertEqual(dry.alreadyImportedCount, 2)
    XCTAssertEqual(dry.unreadable, [["06/11/2026", "FEE", "", "REF5"]])
  }

  /// Eight rows, REF1 and REF4 already stored. Six are new; the sample is the
  /// first five of them in file order, with their data-row indexes as ids.
  func testSampleIsFirstFiveNewInFileOrder() async throws {
    var lines = ["Date,Narration,Amount,Reference"]
    for index in 0..<8 {
      lines.append(String(format: "%02d/11/2026,ROW %d,%d.00,REF%d", index + 1, index, 100 + index, index))
    }
    let url = try write(Self.csv(lines))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(
      pipeline: RecordingIngester(), lookup: StubLookup(ids: ["REF1", "REF4"]))

    let dry = try await service.dryRun(url, mapping: withReference)

    XCTAssertEqual(dry.newCount, 6)
    XCTAssertEqual(dry.alreadyImportedCount, 2)
    XCTAssertEqual(dry.sample.map(\.id), [0, 2, 3, 5, 6])
    XCTAssertEqual(dry.sample.map(\.descriptionText), ["ROW 0", "ROW 2", "ROW 3", "ROW 5", "ROW 6"])
    XCTAssertEqual(dry.sample.first?.amountMinor, 10_000)
    XCTAssertEqual(dry.sample.first?.direction, .credit)
  }

  /// Two identical lines with no reference are two rows: L10 keeps both, so
  /// both count as new (tier 4). The commit would create both too, or merge the
  /// second at tier 4 and say so in its own summary.
  func testTwoIdenticalLinesAreBothNew() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount",
      "02/11/2026,SWIGGY,450.00",
      "02/11/2026,SWIGGY,450.00",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(pipeline: RecordingIngester(), lookup: StubLookup(ids: []))

    let dry = try await service.dryRun(url, mapping: withoutReference)

    XCTAssertEqual(dry.newCount, 2)
    XCTAssertEqual(dry.alreadyImportedCount, 0)
    XCTAssertEqual(dry.sample.map(\.id), [0, 1])
  }

  /// With no lookup there is no store to compare against, so nothing is
  /// already imported and every parsed row is new.
  func testNoLookupMeansNothingAlreadyImported() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(pipeline: RecordingIngester())

    let dry = try await service.dryRun(url, mapping: withReference)

    XCTAssertEqual(dry.newCount, 3)
    XCTAssertEqual(dry.alreadyImportedCount, 0)
  }

  /// A file no row of which maps: the count is zero, every row is unreadable,
  /// and the commit refuses. S11 uses this shape to open Fix columns.
  func testFileNothingMapsCountsZeroAndListsEveryRow() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount",
      "03/11/2026,FEE,",
      "04/11/2026,REVERSAL,",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(pipeline: RecordingIngester(), lookup: StubLookup(ids: []))

    let dry = try await service.dryRun(url, mapping: withoutReference)

    XCTAssertEqual(dry.newCount, 0)
    XCTAssertEqual(dry.alreadyImportedCount, 0)
    XCTAssertEqual(dry.unreadable, [["03/11/2026", "FEE", ""], ["04/11/2026", "REVERSAL", ""]])
    XCTAssertTrue(dry.sample.isEmpty)

    do {
      _ = try await service.commit(url, mapping: withoutReference, accountID: nil)
      XCTFail("a file with no parseable rows must not commit")
    } catch ImportError.noParseableRows {
      // Expected: the dry run's zero and the commit's refusal agree.
    }
  }

  // MARK: - Writes and failures

  /// The pipeline is the only write path. A dry run must not hand it a batch.
  func testDryRunWritesNothing() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let ingester = RecordingIngester()
    let service = FileImportServiceImpl(pipeline: ingester, lookup: StubLookup(ids: ["REF1"]))

    _ = try await service.dryRun(url, mapping: withReference)

    let batches = await ingester.batchCount
    let drafts = await ingester.draftCount
    XCTAssertEqual(batches, 0, "a dry run must not call ingest")
    XCTAssertEqual(drafts, 0)
  }

  /// A failed lookup is a failure, never a zero: the screen must not show
  /// "0 already in Nomi" because the store could not be read.
  func testLookupFailureThrows() async throws {
    let url = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }
    let service = FileImportServiceImpl(pipeline: RecordingIngester(), lookup: FailingLookup())

    do {
      _ = try await service.dryRun(url, mapping: withReference)
      XCTFail("a failed lookup must throw, not count as zero")
    } catch is FailingLookup.LookupFailed {
      // Expected.
    }
  }

  // MARK: - Agreement with commit

  /// One fixture per shape a bank export takes. Each is run through `dryRun` and
  /// `commit` under the same mapping: the new count must equal what commit
  /// imports, and the unreadable count must equal what commit skips. Shapes are
  /// the ones the preview-and-commit agreement test already covers.
  private struct Shape {
    let name: String
    let bytes: Data
    let parsed: Int
    let skipped: Int
  }

  /// Shapes are asserted exactly. The CRLF shape was once a strict known failure
  /// (CSVParser read "\r\n" as one Character); #171 fixed that, so it is an
  /// ordinary case now.
  private static let shapes: [Shape] = [
    // The D13 statement: an empty Withdrawal cell on the salary row, so that row
    // is skipped and three rows import.
    Shape(
      name: "d13-statement",
      bytes: csv([
        "Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance",
        "02/11/2026,UPI-SWIGGY-ORDER 1234,450.00,,10000.00",
        "03/11/2026,NEFT SALARY ACME,,50000.00,60000.00",
        "04/11/2026,POS AMAZON RETAIL,1299.00,,58701.00",
        "05/11/2026,UPI-UBER INDIA,320.00,,58381.00",
      ]),
      parsed: 3, skipped: 1
    ),
    Shape(
      name: "header-variants",
      bytes: csv([
        " date ,NARRATION , Amount (INR) ,Ref No",
        "02/11/2026,SWIGGY,450.00,R1",
        "03/11/2026,ZOMATO,120.00,R2",
      ]),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "blank-lines",
      bytes: csv([
        "Date,Narration,Amount",
        "",
        "02/11/2026,SWIGGY,450.00",
        "   ",
        "",
        "03/11/2026,ZOMATO,120.00",
        "",
      ]),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "quoted-fields",
      bytes: csv([
        "Date,Narration,Amount",
        "\"02/11/2026\",\"SWIGGY, BANGALORE \"\"HSR\"\"\",\"-450.00\"",
        "\"03/11/2026\",\"ZOMATO\nMULTILINE\",\"1,299.00\"",
      ]),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "bom",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,ZOMATO,120.00"], bom: true),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "crlf",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,ZOMATO,120.00"], eol: "\r\n"),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "unparseable-date-among-good-rows",
      bytes: csv([
        "Date,Narration,Amount",
        "02/11/2026,SWIGGY,450.00",
        "31/13/2026,BAD DATE,100.00",
        "03/11/2026,ZOMATO,120.00",
      ]),
      parsed: 2, skipped: 1
    ),
    Shape(
      name: "bom-quoted-blank-and-bad-date-together",
      bytes: csv([
        "Date,Narration,Amount",
        "",
        "02/11/2026,\"SWIGGY, HSR\",\"450.00\"",
        "31/13/2026,BAD DATE,100.00",
        "",
        "03/11/2026,ZOMATO,\"1,299.00\"",
      ], bom: true),
      parsed: 2, skipped: 1
    ),
    Shape(
      name: "identical-rows-are-both-kept",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "02/11/2026,SWIGGY,450.00"]),
      parsed: 2, skipped: 0
    ),
    Shape(
      name: "empty-and-zero-amounts-are-skipped",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,FEE,", "04/11/2026,REVERSAL,0.00"]),
      parsed: 1, skipped: 2
    ),
  ]

  func testDryRunNewCountAgreesWithCommitForEveryFixtureShape() async throws {
    for shape in Self.shapes {
      let url = try write(shape.bytes)
      defer { try? FileManager.default.removeItem(at: url) }
      let service = FileImportServiceImpl(pipeline: RecordingIngester())

      let dry = try await service.dryRun(url, mapping: withoutReference)
      let committed: ImportSummary?
      do {
        committed = try await service.commit(url, mapping: withoutReference, accountID: nil)
      } catch ImportError.noParseableRows {
        committed = nil
      }
      let imported = committed.map { $0.created + $0.merged } ?? 0

      XCTAssertEqual(
        dry.newCount, imported,
        "\(shape.name): the dry run's new count and the rows the commit imports must agree")
      XCTAssertEqual(dry.alreadyImportedCount, 0, "\(shape.name): nothing stored, nothing already imported")
      XCTAssertEqual(dry.newCount, shape.parsed, "\(shape.name): new count")
      XCTAssertEqual(dry.unreadable.count, shape.skipped, "\(shape.name): unreadable rows")
      XCTAssertEqual(committed?.skipped, shape.skipped, "\(shape.name): rows commit skips")
    }
  }

  // MARK: - Against the real store

  /// Containers the test case holds. A container the test lets go of traps
  /// mid-test, so none is returned without being kept here.
  private var keptContainers: [ModelContainer] = []

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema(NomiSchemaV1.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    keptContainers.append(container)
    return container
  }

  /// The service the app builds: the same store is the pipeline's sink and the
  /// dry run's lookup (AppEnvironment).
  private func makeService(store: SwiftDataPipelineStore) -> FileImportServiceImpl {
    let pipeline = IngestPipeline(
      store: store, calendar: Fixture.calendar, transferCalendar: Fixture.calendar, now: Fixture.clock)
    return FileImportServiceImpl(pipeline: pipeline, now: Fixture.clock, lookup: store)
  }

  /// The store reports only `.file` externalIDs: an email row's ID is not an
  /// import ID, so it must not make a file row "already in Nomi".
  func testLookupReadsOnlyFileSourceRefs() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let pipeline = IngestPipeline(
      store: store, calendar: Fixture.calendar, transferCalendar: Fixture.calendar, now: Fixture.clock)
    _ = try await pipeline.ingest([
      TransactionDraft(
        date: Fixture.date("2026-11-02"), descriptionText: "SWIGGY", amountMinor: 45_000,
        direction: .debit, source: .email, externalID: "MAIL-1"),
      TransactionDraft(
        date: Fixture.date("2026-11-03"), descriptionText: "ZOMATO", amountMinor: 12_000,
        direction: .debit, source: .file, externalID: "FILE-1"),
    ])

    let fileIDs = try await store.externalIDs(source: .file)
    let mailIDs = try await store.externalIDs(source: .email)

    XCTAssertEqual(fileIDs, ["FILE-1"])
    XCTAssertEqual(mailIDs, ["MAIL-1"])
  }

  /// Commit, then the same file again: the dry run reads the rows commit wrote.
  /// New equals created on the first commit, and the second dry run is all
  /// already imported with nothing new, matching the second commit's zero.
  func testStoredRowsAreAlreadyImportedAndDryRunMatchesCommit() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let service = makeService(store: store)
    let url = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
    ]))
    defer { try? FileManager.default.removeItem(at: url) }

    let rowsBefore = try ModelContext(container).fetchCount(FetchDescriptor<Transaction>())
    let firstDry = try await service.dryRun(url, mapping: withReference)
    let rowsAfterDry = try ModelContext(container).fetchCount(FetchDescriptor<Transaction>())
    XCTAssertEqual(rowsAfterDry, rowsBefore, "a dry run writes no row")
    XCTAssertEqual(firstDry.newCount, 3)
    XCTAssertEqual(firstDry.alreadyImportedCount, 0)

    let firstCommit = try await service.commit(url, mapping: withReference, accountID: nil)
    XCTAssertEqual(firstCommit.created, firstDry.newCount, "first commit: new rows equal created rows")

    let secondDry = try await service.dryRun(url, mapping: withReference)
    XCTAssertEqual(secondDry.newCount, 0)
    XCTAssertEqual(secondDry.alreadyImportedCount, 3)
    XCTAssertTrue(secondDry.sample.isEmpty)

    let secondCommit = try await service.commit(url, mapping: withReference, accountID: nil)
    XCTAssertEqual(secondCommit.created, secondDry.newCount, "re-import: new rows equal created rows")
  }

  /// An overlapping statement: two rows are stored, two are new. The dry run
  /// reports 2 new and 2 already, and the commit creates the 2 new.
  func testOverlappingStatementCountsOnlyTheNewRows() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let service = makeService(store: store)
    let first = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
    ]))
    defer { try? FileManager.default.removeItem(at: first) }
    _ = try await service.commit(first, mapping: withReference, accountID: nil)

    let overlap = try write(Self.csv([
      "Date,Narration,Amount,Reference",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
      "05/11/2026,BIGBASKET,60.00,REF4",
      "06/11/2026,OLA,30.00,REF5",
    ]))
    defer { try? FileManager.default.removeItem(at: overlap) }

    let dry = try await service.dryRun(overlap, mapping: withReference)
    XCTAssertEqual(dry.newCount, 2)
    XCTAssertEqual(dry.alreadyImportedCount, 2)
    XCTAssertEqual(dry.sample.map(\.id), [2, 3])

    let summary = try await service.commit(overlap, mapping: withReference, accountID: nil)
    XCTAssertEqual(summary.created, dry.newCount, "new rows equal created rows")
    XCTAssertEqual(summary.merged, dry.alreadyImportedCount, "already-imported rows are merged, not created")
  }
}
