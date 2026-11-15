import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// B4 and B4b (I-12, Amendment 1): `FileImportService.dryRun` runs the pipeline's
/// own ingest loop without writing, so its counts are commit's counts. Every case
/// here runs a real `IngestPipeline` over a real `SwiftDataPipelineStore`, wrapped
/// in a spy that counts the writes that reach the store. Each case checks dry run
/// against commit field by field, with no write in between.
///
/// **XCTest, and it has to stay XCTest**, as `SwiftDataPipelineStoreTests` does.
/// Every container is kept in a stored property of the test case: a container the
/// test lets go of traps mid-test.
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

  private static let header = "Date,Narration,Amount,Reference"

  /// Containers the test case holds, and files it wrote. Removed in `tearDown`.
  private var keptContainers: [ModelContainer] = []
  private var tempFiles: [URL] = []

  override func tearDown() {
    for url in tempFiles { try? FileManager.default.removeItem(at: url) }
    tempFiles = []
    super.tearDown()
  }

  // MARK: - Doubles

  /// Forwards every call to the real store and counts the writes, so "a dry run
  /// writes nothing" is checked at the store and not inferred from the counts.
  private actor WriteSpyStore: PipelineStore {
    private let inner: SwiftDataPipelineStore
    private(set) var applyCount = 0
    private(set) var transferMarkCount = 0

    init(_ inner: SwiftDataPipelineStore) {
      self.inner = inner
    }

    func rules() async throws -> [RuleSnapshot] {
      try await inner.rules()
    }

    func mergeCandidates(
      amountMinor: Int,
      directionRaw: String,
      dateRange: ClosedRange<Date>
    ) async throws -> [TransactionSnapshot] {
      try await inner.mergeCandidates(amountMinor: amountMinor, directionRaw: directionRaw, dateRange: dateRange)
    }

    func duplicateGroups() async throws -> [[TransactionSnapshot]] {
      try await inner.duplicateGroups()
    }

    func apply(_ plan: CommitPlan) async throws {
      applyCount += 1
      try await inner.apply(plan)
    }

    func accountFacts() async throws -> [UUID: TransferAccount] {
      try await inner.accountFacts()
    }

    func transferCandidates(
      amountMinor: Int,
      dateRange: ClosedRange<Date>
    ) async throws -> [TransactionSnapshot] {
      try await inner.transferCandidates(amountMinor: amountMinor, dateRange: dateRange)
    }

    func applyTransferMarks(
      _ writes: [TransferPairWrite],
      updatedAt: Date
    ) async throws -> [TransferPairWrite] {
      transferMarkCount += 1
      return try await inner.applyTransferMarks(writes, updatedAt: updatedAt)
    }
  }

  /// One service over one store, with the spies a test reads.
  private struct Rig {
    let service: FileImportServiceImpl
    let spy: WriteSpyStore
    let observer: RecordingObserver
    let container: ModelContainer
  }

  // MARK: - Fixtures

  /// Builds a file's bytes from its lines. `eol` is the line ending, and `bom`
  /// prefixes the UTF-8 byte-order mark Excel writes.
  private static func csv(_ lines: [String], eol: String = "\n", bom: Bool = false) -> Data {
    var data = bom ? Data([0xEF, 0xBB, 0xBF]) : Data()
    data.append(Data((lines.joined(separator: eol) + eol).utf8))
    return data
  }

  /// Writes `bytes` to a fresh temporary file, removed in `tearDown`.
  private func write(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-dryrun-\(UUID().uuidString).csv")
    try bytes.write(to: url)
    tempFiles.append(url)
    return url
  }

  /// A file with the reference header and the given data rows.
  private func writeRows(_ rows: [String]) throws -> URL {
    try write(Self.csv([Self.header] + rows))
  }

  /// Data row `index` as the numbered fixtures use it: a distinct amount and day,
  /// and reference `REF<index>`.
  private static func numberedRow(_ index: Int) -> String {
    String(format: "%02d/11/2026,ROW %d,%d.00,REF%d", index + 1, index, 100 + index, index)
  }

  /// Sixty rows. Row 1 and row 60 are the same line, so the repeat is split across
  /// the pipeline's 50-row chunks: row 60 is the tenth row of the second chunk.
  private static func acrossChunksRows() -> [String] {
    var rows = ["02/11/2026,DUP ROW,450.00,REFDUP"]
    for index in 1...58 {
      rows.append("02/11/2026,ROW \(index),\(100 + index).00,REFR\(index)")
    }
    rows.append("02/11/2026,DUP ROW,450.00,REFDUP")
    return rows
  }

  /// A rig over a fresh in-memory store. The pipeline and the service share the
  /// same clock, so commit and dry run see the same capture time.
  private func makeRig() async throws -> Rig {
    let container = try makeContainer()
    let spy = WriteSpyStore(SwiftDataPipelineStore(modelContainer: container))
    let observer = RecordingObserver()
    let pipeline = IngestPipeline(
      store: spy, calendar: Fixture.calendar, transferCalendar: Fixture.calendar, now: Fixture.clock)
    await pipeline.setObserver(observer)
    let service = FileImportServiceImpl(pipeline: pipeline, now: Fixture.clock)
    return Rig(service: service, spy: spy, observer: observer, container: container)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema(NomiSchemaV1.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    keptContainers.append(container)
    return container
  }

  /// Every stored Transaction, in id order, as the pipeline reads and writes it:
  /// narration, category, source refs, timestamps, transfer pair and so on.
  private func storedSnapshots(_ container: ModelContainer) throws -> [TransactionSnapshot] {
    let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
    return rows.map { TransactionSnapshot($0) }.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  private func storedCount(_ container: ModelContainer) throws -> Int {
    try ModelContext(container).fetchCount(FetchDescriptor<Transaction>())
  }

  /// Runs dry run, then commit, on one file with no write between them, and checks
  /// the I-12 agreement field by field: create, matched existing and repeated in
  /// file, plus unreadable against skipped.
  private func dryRunThenCommit(
    _ rig: Rig,
    _ url: URL,
    mapping: ColumnMapping,
    label: String
  ) async throws -> (dry: ImportDryRun, commit: ImportSummary) {
    let dry = try await rig.service.dryRun(url, mapping: mapping)
    let commit = try await rig.service.commit(url, mapping: mapping, accountID: nil)
    XCTAssertEqual(dry.createCount, commit.created, "\(label): create")
    XCTAssertEqual(dry.matchExistingCount, commit.matchedExisting, "\(label): matched existing")
    XCTAssertEqual(dry.repeatInFileCount, commit.repeatedInFile, "\(label): repeated in file")
    XCTAssertEqual(commit.merged, commit.matchedExisting + commit.repeatedInFile, "\(label): merged is the sum")
    XCTAssertEqual(dry.unreadable.count, commit.skipped, "\(label): unreadable against skipped")
    return (dry, commit)
  }

  // MARK: - Counts

  /// Five data rows: two new, two already stored, and one with no amount. Dry run
  /// and commit both say 2 created, 2 matched, 0 repeated, 1 unreadable.
  func testCountsCreateMatchAndUnreadable() async throws {
    let rig = try await makeRig()
    let prior = try writeRows([
      "04/11/2026,OLD ONE,10.00,REF3",
      "05/11/2026,OLD TWO,20.00,REF4",
    ])
    _ = try await rig.service.commit(prior, mapping: withReference, accountID: nil)
    let url = try writeRows([
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,OLD ONE,10.00,REF3",
      "05/11/2026,OLD TWO,20.00,REF4",
      "06/11/2026,FEE,,REF5",
    ])

    let (dry, _) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "five-rows")

    XCTAssertEqual(dry.createCount, 2)
    XCTAssertEqual(dry.matchExistingCount, 2)
    XCTAssertEqual(dry.repeatInFileCount, 0)
    XCTAssertEqual(dry.unreadable, [["06/11/2026", "FEE", "", "REF5"]])
  }

  /// Eight rows, REF1 and REF4 already stored. Six are created; the sample is the
  /// first five of them in file order, with their data-row indexes as ids.
  func testSampleIsFirstFiveCreatedInFileOrder() async throws {
    let rig = try await makeRig()
    _ = try await rig.service.commit(
      try writeRows([Self.numberedRow(1), Self.numberedRow(4)]), mapping: withReference, accountID: nil)
    let url = try writeRows((0..<8).map(Self.numberedRow))

    let (dry, _) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "numbered")

    XCTAssertEqual(dry.createCount, 6)
    XCTAssertEqual(dry.matchExistingCount, 2)
    XCTAssertEqual(dry.repeatInFileCount, 0)
    XCTAssertEqual(dry.sample.map(\.id), [0, 2, 3, 5, 6])
    XCTAssertEqual(dry.sample.map(\.descriptionText), ["ROW 0", "ROW 2", "ROW 3", "ROW 5", "ROW 6"])
    XCTAssertEqual(dry.sample.first?.amountMinor, 10_000)
    XCTAssertEqual(dry.sample.first?.direction, .credit)
  }

  /// The sample names the rows that will be created, by data-row index. With a
  /// repeat before a new row, the new row is index 2; with the repeat after, index
  /// 1. The draft index is what tells the two apart (I-12, Amendment 1).
  func testSampleIndexesFollowDraftOrderWhenARepeatComesFirst() async throws {
    let a = "02/11/2026,SWIGGY,450.00,REFA"
    let b = "03/11/2026,ZOMATO,120.00,REFB"

    let firstRig = try await makeRig()
    let first = try writeRows([a, b, a])
    let (firstDry, _) = try await dryRunThenCommit(firstRig, first, mapping: withReference, label: "A B A")
    XCTAssertEqual(firstDry.sample.map(\.id), [0, 1], "A B A: the repeat is last, so the new rows are 0 and 1")
    XCTAssertEqual(firstDry.repeatInFileCount, 1)

    let secondRig = try await makeRig()
    let second = try writeRows([a, a, b])
    let (secondDry, _) = try await dryRunThenCommit(secondRig, second, mapping: withReference, label: "A A B")
    XCTAssertEqual(secondDry.sample.map(\.id), [0, 2], "A A B: the repeat is 1, so the new rows are 0 and 2")
    XCTAssertEqual(secondDry.repeatInFileCount, 1)
  }

  /// Two identical lines with no reference are two rows, but commit folds the
  /// second into the first. The pin follows commit (B4b replaces B4's both-new
  /// test).
  func testTwoIdenticalLinesAreOneNewAndOneRepeat() async throws {
    let rig = try await makeRig()
    let url = try write(Self.csv([
      "Date,Narration,Amount",
      "02/11/2026,SWIGGY,450.00",
      "02/11/2026,SWIGGY,450.00",
    ]))

    let (dry, _) = try await dryRunThenCommit(rig, url, mapping: withoutReference, label: "identical")

    XCTAssertEqual(dry.createCount, 1)
    XCTAssertEqual(dry.matchExistingCount, 0)
    XCTAssertEqual(dry.repeatInFileCount, 1)
    XCTAssertEqual(dry.sample.map(\.id), [0])
  }

  /// With nothing stored, every parsed row is created: the empty-store case that
  /// the lookup used to stand for.
  func testEmptyStoreCreatesEveryRow() async throws {
    let rig = try await makeRig()
    let url = try writeRows([
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
    ])

    let (dry, _) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "empty")

    XCTAssertEqual(dry.createCount, 3)
    XCTAssertEqual(dry.matchExistingCount, 0)
    XCTAssertEqual(dry.repeatInFileCount, 0)
  }

  /// A file no row of which maps: every count is zero, every row is unreadable,
  /// and the commit refuses. S11 uses this shape to open Fix columns.
  func testFileNothingMapsCountsZeroAndListsEveryRow() async throws {
    let rig = try await makeRig()
    let url = try write(Self.csv([
      "Date,Narration,Amount",
      "03/11/2026,FEE,",
      "04/11/2026,REVERSAL,",
    ]))

    let dry = try await rig.service.dryRun(url, mapping: withoutReference)

    XCTAssertEqual(dry.createCount, 0)
    XCTAssertEqual(dry.matchExistingCount, 0)
    XCTAssertEqual(dry.repeatInFileCount, 0)
    XCTAssertEqual(dry.unreadable, [["03/11/2026", "FEE", ""], ["04/11/2026", "REVERSAL", ""]])
    XCTAssertTrue(dry.sample.isEmpty)

    do {
      _ = try await rig.service.commit(url, mapping: withoutReference, accountID: nil)
      XCTFail("a file with no parseable rows must not commit")
    } catch ImportError.noParseableRows {
      // Expected: the dry run's zero and the commit's refusal agree.
    }
  }

  // MARK: - Writes

  /// I-12: the pipeline's ingest loop runs without writing. A commit stores two
  /// rows; a dry run of an overlapping file then runs against them. The store's
  /// row count and rows, the apply and transfer-mark calls and the observer must
  /// all be unchanged.
  func testDryRunWritesNothing() async throws {
    let rig = try await makeRig()
    _ = try await rig.service.commit(
      try writeRows(["02/11/2026,SWIGGY,450.00,REF1", "03/11/2026,ZOMATO,120.00,REF2"]),
      mapping: withReference, accountID: nil)

    let rowsBefore = try storedCount(rig.container)
    let rowSnapshotsBefore = try storedSnapshots(rig.container)
    let applyBefore = await rig.spy.applyCount
    let transferMarksBefore = await rig.spy.transferMarkCount
    let observedBefore = rig.observer.callCount

    let overlap = try writeRows(["03/11/2026,ZOMATO,120.00,REF2", "04/11/2026,UBER,80.00,REF3"])
    let dry = try await rig.service.dryRun(overlap, mapping: withReference)
    XCTAssertEqual(dry.createCount, 1, "the dry run answers while writing nothing")
    XCTAssertEqual(dry.matchExistingCount, 1)

    let rowsAfter = try storedCount(rig.container)
    let rowSnapshotsAfter = try storedSnapshots(rig.container)
    let applyAfter = await rig.spy.applyCount
    let transferMarksAfter = await rig.spy.transferMarkCount
    XCTAssertEqual(rowsAfter, rowsBefore, "a dry run writes no row")
    XCTAssertEqual(rowSnapshotsAfter, rowSnapshotsBefore, "a dry run changes no stored field")
    XCTAssertEqual(applyAfter, applyBefore, "a dry run never calls apply")
    XCTAssertEqual(transferMarksAfter, transferMarksBefore, "a dry run never marks transfers")
    XCTAssertEqual(rig.observer.callCount, observedBefore, "a dry run never notifies the observer")
  }

  // MARK: - Agreement with commit

  /// One fixture per shape a bank export takes. Each is run through dry run and
  /// commit under the same mapping: create, matched and repeated must equal what
  /// commit makes of the file, and the unreadable count must equal what commit
  /// skips. `repeats` is the number of rows that fold into an earlier row.
  private struct Shape {
    let name: String
    let bytes: Data
    let parsed: Int
    let skipped: Int
    let repeats: Int
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
      parsed: 3, skipped: 1, repeats: 0
    ),
    Shape(
      name: "header-variants",
      bytes: csv([
        " date ,NARRATION , Amount (INR) ,Ref No",
        "02/11/2026,SWIGGY,450.00,R1",
        "03/11/2026,ZOMATO,120.00,R2",
      ]),
      parsed: 2, skipped: 0, repeats: 0
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
      parsed: 2, skipped: 0, repeats: 0
    ),
    Shape(
      name: "quoted-fields",
      bytes: csv([
        "Date,Narration,Amount",
        "\"02/11/2026\",\"SWIGGY, BANGALORE \"\"HSR\"\"\",\"-450.00\"",
        "\"03/11/2026\",\"ZOMATO\nMULTILINE\",\"1,299.00\"",
      ]),
      parsed: 2, skipped: 0, repeats: 0
    ),
    Shape(
      name: "bom",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,ZOMATO,120.00"], bom: true),
      parsed: 2, skipped: 0, repeats: 0
    ),
    Shape(
      name: "crlf",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,ZOMATO,120.00"], eol: "\r\n"),
      parsed: 2, skipped: 0, repeats: 0
    ),
    Shape(
      name: "unparseable-date-among-good-rows",
      bytes: csv([
        "Date,Narration,Amount",
        "02/11/2026,SWIGGY,450.00",
        "31/13/2026,BAD DATE,100.00",
        "03/11/2026,ZOMATO,120.00",
      ]),
      parsed: 2, skipped: 1, repeats: 0
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
      parsed: 2, skipped: 1, repeats: 0
    ),
    Shape(
      name: "identical-rows-are-one-new-and-one-repeat",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "02/11/2026,SWIGGY,450.00"]),
      parsed: 2, skipped: 0, repeats: 1
    ),
    Shape(
      name: "empty-and-zero-amounts-are-skipped",
      bytes: csv(["Date,Narration,Amount", "02/11/2026,SWIGGY,450.00", "03/11/2026,FEE,", "04/11/2026,REVERSAL,0.00"]),
      parsed: 1, skipped: 2, repeats: 0
    ),
  ]

  func testDryRunAgreesWithCommitForEveryFixtureShape() async throws {
    for shape in Self.shapes {
      let rig = try await makeRig()
      let url = try write(shape.bytes)

      let (dry, commit) = try await dryRunThenCommit(
        rig, url, mapping: withoutReference, label: shape.name)

      XCTAssertEqual(dry.createCount, shape.parsed - shape.repeats, "\(shape.name): create")
      XCTAssertEqual(dry.matchExistingCount, 0, "\(shape.name): nothing stored, nothing matched")
      XCTAssertEqual(dry.repeatInFileCount, shape.repeats, "\(shape.name): repeats")
      XCTAssertEqual(dry.unreadable.count, shape.skipped, "\(shape.name): unreadable rows")
      XCTAssertEqual(commit.skipped, shape.skipped, "\(shape.name): rows commit skips")
    }
  }

  /// The fixture table. Each case is a file, optionally preceded by a commit of
  /// `prior` rows so that some are already in Nomi. The expected counts are what
  /// the rule gives by hand, and dry run and commit must both agree with them.
  private struct DryRunCase {
    let name: String
    let prior: [String]
    let rows: [String]
    let create: Int
    let match: Int
    let repeats: Int
    let sample: [Int]
  }

  private static let cases: [DryRunCase] = [
    // Lim's PR #216 case: ref A, ref A again, two rows imported before, one new.
    // A and the new row are created; the second A folds into the first; the two
    // stored rows match.
    DryRunCase(
      name: "lim-pr216",
      prior: [
        "03/11/2026,ZOMATO,120.00,REFE1",
        "04/11/2026,OLA,30.00,REFE2",
      ],
      rows: [
        "02/11/2026,UBER,80.00,REFA",
        "02/11/2026,UBER,80.00,REFA",
        "03/11/2026,ZOMATO,120.00,REFE1",
        "04/11/2026,OLA,30.00,REFE2",
        "05/11/2026,BIGBASKET,60.00,REFN",
      ],
      create: 2, match: 2, repeats: 1, sample: [0, 4]),
    // Five distinct new rows.
    DryRunCase(
      name: "five-distinct-new",
      prior: [],
      rows: [
        "01/11/2026,SHOP ONE,10.00,REFD1",
        "02/11/2026,SHOP TWO,20.00,REFD2",
        "03/11/2026,SHOP THREE,30.00,REFD3",
        "04/11/2026,SHOP FOUR,40.00,REFD4",
        "05/11/2026,SHOP FIVE,50.00,REFD5",
      ],
      create: 5, match: 0, repeats: 0, sample: [0, 1, 2, 3, 4]),
    // The same file imported a second time: every row is already in Nomi.
    DryRunCase(
      name: "same-file-second-run",
      prior: [
        "01/11/2026,SHOP ONE,10.00,REFD1",
        "02/11/2026,SHOP TWO,20.00,REFD2",
        "03/11/2026,SHOP THREE,30.00,REFD3",
        "04/11/2026,SHOP FOUR,40.00,REFD4",
        "05/11/2026,SHOP FIVE,50.00,REFD5",
      ],
      rows: [
        "01/11/2026,SHOP ONE,10.00,REFD1",
        "02/11/2026,SHOP TWO,20.00,REFD2",
        "03/11/2026,SHOP THREE,30.00,REFD3",
        "04/11/2026,SHOP FOUR,40.00,REFD4",
        "05/11/2026,SHOP FIVE,50.00,REFD5",
      ],
      create: 0, match: 5, repeats: 0, sample: []),
    // Same narration, amount and date, two references. The matcher treats them as
    // one payment, so the second folds into the first.
    DryRunCase(
      name: "same-narration-different-references",
      prior: [],
      rows: [
        "02/11/2026,SWIGGY,450.00,REFA",
        "02/11/2026,SWIGGY,450.00,REFB",
      ],
      create: 1, match: 0, repeats: 1, sample: [0]),
    // Sixty rows; row 1 and row 60 are identical, so the repeat crosses the
    // 50-row chunk boundary and must still be seen as a repeat of a row this
    // import created.
    DryRunCase(
      name: "repeat-split-across-chunks",
      prior: [],
      rows: acrossChunksRows(),
      create: 59, match: 0, repeats: 1, sample: [0, 1, 2, 3, 4]),
  ]

  /// Every fixture case: dry run and commit agree, and the three counts add up to
  /// the parsed rows, the invariant I-12 Amendment 1 states.
  func testCountsAddUpToParsedRows() async throws {
    for testCase in Self.cases {
      let rig = try await makeRig()
      if !testCase.prior.isEmpty {
        _ = try await rig.service.commit(
          try writeRows(testCase.prior), mapping: withReference, accountID: nil)
      }
      let url = try writeRows(testCase.rows)

      let (dry, commit) = try await dryRunThenCommit(
        rig, url, mapping: withReference, label: testCase.name)

      let parsed = testCase.rows.count
      XCTAssertEqual(
        dry.createCount + dry.matchExistingCount + dry.repeatInFileCount, parsed,
        "\(testCase.name): create + match + repeat equals the parsed rows")
      XCTAssertEqual(commit.created + commit.merged, parsed, "\(testCase.name): commit creates or merges every row")
      XCTAssertEqual(dry.createCount, testCase.create, "\(testCase.name): create")
      XCTAssertEqual(dry.matchExistingCount, testCase.match, "\(testCase.name): match")
      XCTAssertEqual(dry.repeatInFileCount, testCase.repeats, "\(testCase.name): repeat")
      XCTAssertEqual(dry.sample.map(\.id), testCase.sample, "\(testCase.name): sample")
    }
  }

  // MARK: - Against the real store

  /// An amount beyond `AmountRules.maximumMinor` is refused by RowMapper (B7, wave-1
  /// Risk 10). The dry run counts that row unreadable, and commit skips it and counts
  /// it in `skipped`, so the two agree.
  func testAmountBeyondTheCapIsUnreadableInTheDryRun() async throws {
    let rig = try await makeRig()
    let url = try writeRows([
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,BIG TRANSFER,2000000000.00,REF2",
    ])

    let (dry, commit) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "over-cap")

    XCTAssertEqual(dry.createCount, 1)
    XCTAssertEqual(dry.matchExistingCount, 0)
    XCTAssertEqual(dry.unreadable, [["03/11/2026", "BIG TRANSFER", "2000000000.00", "REF2"]])
    XCTAssertEqual(dry.sample.map(\.id), [0])
    XCTAssertEqual(commit.created + commit.merged, 1, "commit skips the over-cap row")
    XCTAssertEqual(commit.skipped, dry.unreadable.count, "rows commit skips must equal dry-run unreadable")
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
  /// Creates equal the first commit's creates, and the second dry run is all
  /// matched, with nothing created, matching the second commit's merges.
  func testStoredRowsAreMatchedAndDryRunMatchesCommit() async throws {
    let rig = try await makeRig()
    let url = try writeRows([
      "02/11/2026,SWIGGY,450.00,REF1",
      "03/11/2026,ZOMATO,120.00,REF2",
      "04/11/2026,UBER,80.00,REF3",
    ])

    let rowsBefore = try storedCount(rig.container)
    let (firstDry, firstCommit) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "first")
    XCTAssertEqual(firstDry.createCount, 3)
    XCTAssertEqual(firstCommit.created, 3, "first commit: created rows equal the dry run")
    XCTAssertEqual(rowsBefore, 0, "nothing was stored before the first commit")

    let secondDry = try await rig.service.dryRun(url, mapping: withReference)
    XCTAssertEqual(secondDry.createCount, 0)
    XCTAssertEqual(secondDry.matchExistingCount, 3)
    XCTAssertTrue(secondDry.sample.isEmpty)

    let secondCommit = try await rig.service.commit(url, mapping: withReference, accountID: nil)
    XCTAssertEqual(secondCommit.created, secondDry.createCount, "re-import: created rows equal the dry run")
    XCTAssertEqual(secondCommit.matchedExisting, secondDry.matchExistingCount, "re-import: matched rows equal the dry run")
    XCTAssertEqual(secondCommit.merged, 3, "re-import of three stored rows: dry 0/3/0, commit created 0, merged 3")
  }

  /// An overlapping statement: three rows are stored, and the file repeats one of
  /// them. Dry run creates 2 and matches 1. Commit creates the 2 and merges the 1
  /// into the stored row.
  func testOverlappingStatementCountsCreateAndMatchSeparately() async throws {
    let rig = try await makeRig()
    _ = try await rig.service.commit(
      try writeRows([
        "02/11/2026,SWIGGY,450.00,REF1",
        "03/11/2026,ZOMATO,120.00,REF2",
        "04/11/2026,UBER,80.00,REF3",
      ]),
      mapping: withReference, accountID: nil)

    let overlap = try writeRows([
      "04/11/2026,UBER,80.00,REF3",
      "05/11/2026,BIGBASKET,60.00,REF4",
      "06/11/2026,OLA,30.00,REF5",
    ])

    let (dry, summary) = try await dryRunThenCommit(rig, overlap, mapping: withReference, label: "overlap")
    XCTAssertEqual(dry.createCount, 2)
    XCTAssertEqual(dry.matchExistingCount, 1)
    XCTAssertEqual(dry.repeatInFileCount, 0)
    XCTAssertEqual(dry.sample.map(\.id), [1, 2])
    XCTAssertEqual(summary.created, 2)
    XCTAssertEqual(summary.merged, 1)
  }

  /// Two rows with one narration, amount and date, under two references. Neither
  /// reference is stored. Commit creates the first and folds the second into it,
  /// so the second is a repeat in this file, not a match with Nomi.
  func testSameNarrationDifferentReferenceIsOneRepeat() async throws {
    let rig = try await makeRig()
    let url = try writeRows([
      "02/11/2026,SWIGGY,450.00,REFA",
      "02/11/2026,SWIGGY,450.00,REFB",
    ])

    let (dry, summary) = try await dryRunThenCommit(rig, url, mapping: withReference, label: "same-narration")
    XCTAssertEqual(dry.createCount, 1)
    XCTAssertEqual(dry.matchExistingCount, 0)
    XCTAssertEqual(dry.repeatInFileCount, 1)
    XCTAssertEqual(summary.repeatedInFile, 1, "the second row folds into the first")
    XCTAssertEqual(summary.matchedExisting, 0)
  }

  /// I-12: a dry run writes nothing. Commit stores three rows; a dry run of an
  /// overlapping file then runs against them. Every stored field of every row must
  /// be unchanged, read back through a fresh context. Lim's M4 (a lookup that saves
  /// a changed narration) fails this test.
  func testDryRunChangesNoStoredField() async throws {
    let rig = try await makeRig()
    _ = try await rig.service.commit(
      try writeRows([
        "02/11/2026,SWIGGY,450.00,REF1",
        "03/11/2026,ZOMATO,120.00,REF2",
        "04/11/2026,UBER,80.00,REF3",
      ]),
      mapping: withReference, accountID: nil)
    let before = try storedSnapshots(rig.container)

    let overlap = try writeRows([
      "04/11/2026,UBER,80.00,REF3",
      "05/11/2026,BIGBASKET,60.00,REF4",
    ])
    _ = try await rig.service.dryRun(overlap, mapping: withReference)

    let after = try storedSnapshots(rig.container)
    XCTAssertEqual(before.count, 3)
    XCTAssertEqual(after, before, "a dry run must not change any stored field of any row")
  }
}
