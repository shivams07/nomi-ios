import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// B7 (wave-1 Risk 10): a file amount is read by the same rule manual entry uses,
/// and an amount outside `AmountRules` is refused rather than truncated. The first
/// group is `RowMapper` alone; the last is commit, which must skip the same rows
/// dry run counts as unreadable.
final class RowMapperAmountTests: XCTestCase {
  /// Columns 0 to 2 as Date, Narration, Amount, signed, dd/MM/yyyy.
  private let signedMapping = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )

  /// Columns 0 to 3 as Date, Narration, debit (2), credit (3).
  private let separateMapping = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .separateColumns(debit: 2, credit: 3), dateFormat: "dd/MM/yyyy"
  )

  /// Columns 0 to 2 as Date, Narration, Amount; the flag is column 3.
  private let flagMapping = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .flagColumn(index: 3, debitValues: ["DEBIT"]), dateFormat: "dd/MM/yyyy"
  )

  private let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return cal
  }()

  /// The one row's mapping, or nil when `RowMapper` refuses it.
  private func map(_ row: [String], _ mapping: ColumnMapping) -> ParsedRow? {
    let mapped = RowMapper.mapAll(
      rows: [row], mapping: mapping, formatSignature: "b7-test", calendar: calendar)
    XCTAssertEqual(mapped.count, 1)
    return mapped.first ?? nil
  }

  /// A signed-amount row carrying `amount` in the Amount column.
  private func signed(_ amount: String) -> ParsedRow? {
    map(["02/11/2026", "SWIGGY", amount], signedMapping)
  }

  // MARK: - The cap, on a signed column

  /// 10^11 paise exactly is `AmountRules.maximumMinor`, and it is accepted.
  func testCapIsAcceptedExactly() {
    XCTAssertEqual(signed("1000000000.00")?.amountMinor, AmountRules.maximumMinor)
  }

  /// Indian grouping of the same figure, ₹1,00,00,00,000.00, is the cap too.
  func testIndianGroupingOfTheCapIsAccepted() {
    XCTAssertEqual(signed("1,00,00,00,000.00")?.amountMinor, AmountRules.maximumMinor)
  }

  /// One paisa over the cap, 10^11 + 1 paise. Lim's probe on PR #206 imported this.
  func testOnePaiseOverTheCapIsRefused() {
    XCTAssertNil(signed("1000000000.01"))
  }

  /// Lim's probe on PR #206: this became 1864712049423024028 paise through
  /// `NSDecimalNumber.intValue`. It must be refused, not truncated.
  func testFarBeyondIntIsRefusedNotTruncated() {
    XCTAssertNil(signed("99999999999999999999.00"))
  }

  func testThirtyDigitsAreRefused() {
    XCTAssertNil(signed("123456789012345678901234567890.00"))
  }

  /// A debit has the same magnitude rule: -10^11 paise is a valid debit, -10^11 - 1 is not.
  func testNegativeAtTheCapIsADebitAtTheCap() {
    let row = signed("-1000000000.00")
    XCTAssertEqual(row?.amountMinor, AmountRules.maximumMinor)
    XCTAssertEqual(row?.direction, .debit)
  }

  func testNegativeOnePaiseOverTheCapIsRefused() {
    XCTAssertNil(signed("-1000000000.01"))
  }

  /// Zero is not an amount to record, and neither is text that is not a number.
  func testZeroAndUnreadableTextAreRefused() {
    XCTAssertNil(signed("0.00"))
    XCTAssertNil(signed("0"))
    XCTAssertNil(signed(""))
    XCTAssertNil(signed("abc"))
    XCTAssertNil(signed("1.2.3"))
  }

  /// The rule is `AmountText.parse`: grouping goes, decimals are at most two places.
  func testFileAmountsFollowTheManualEntryRule() {
    XCTAssertEqual(signed("450.5")?.amountMinor, 45_050)
    XCTAssertEqual(signed("1,234.50")?.amountMinor, 123_450)
    XCTAssertNil(signed("450.555"), "three decimal places are refused, as in manual entry")
  }

  // MARK: - The cap, on separate debit and credit columns

  /// An over-cap debit refuses the row. It must not fall through to the credit
  /// column and import the 500.00 beside it as a credit.
  func testOverCapDebitRefusesTheRowAndDoesNotReadTheCredit() {
    XCTAssertNil(map(["02/11/2026", "SWIGGY", "2000000000.00", "500.00"], separateMapping))
  }

  func testOnePaiseOverCapDebitIsRefused() {
    XCTAssertNil(map(["02/11/2026", "SWIGGY", "1000000000.01", ""], separateMapping))
  }

  func testCapDebitIsAccepted() {
    let row = map(["02/11/2026", "SWIGGY", "1000000000.00", ""], separateMapping)
    XCTAssertEqual(row?.amountMinor, AmountRules.maximumMinor)
    XCTAssertEqual(row?.direction, .debit)
  }

  /// A blank or dash cell in the unused column still reads as zero, as bank
  /// presets rely on, so the credit is imported.
  func testBlankAndDashCellsStillReadAsZero() {
    let blank = map(["02/11/2026", "SALARY", "", "500.00"], separateMapping)
    XCTAssertEqual(blank?.amountMinor, 50_000)
    XCTAssertEqual(blank?.direction, .credit)

    let dash = map(["02/11/2026", "SALARY", "-", "500.00"], separateMapping)
    XCTAssertEqual(dash?.amountMinor, 50_000)
    XCTAssertEqual(dash?.direction, .credit)
  }

  /// A negative debit is not a debit, and with no credit the row is refused.
  func testNegativeDebitWithNoCreditIsRefused() {
    XCTAssertNil(map(["02/11/2026", "FEE", "-500.00", ""], separateMapping))
  }

  // MARK: - The cap, on a flag column

  func testOverCapFlaggedAmountIsRefused() {
    XCTAssertNil(map(["02/11/2026", "TRANSFER", "2000000000.00", "DEBIT"], flagMapping))
  }

  func testCapFlaggedAmountIsAccepted() {
    let row = map(["02/11/2026", "TRANSFER", "1000000000.00", "DEBIT"], flagMapping)
    XCTAssertEqual(row?.amountMinor, AmountRules.maximumMinor)
    XCTAssertEqual(row?.direction, .debit)
  }

  // MARK: - Commit skips what dry run counts unreadable

  private actor CapturingIngester: DraftIngesting {
    private(set) var drafts: [TransactionDraft] = []

    func ingest(_ batch: [TransactionDraft]) async throws -> IngestBatchResult {
      drafts.append(contentsOf: batch)
      return IngestBatchResult(created: batch.count, merged: 0, flagged: 0)
    }
  }

  private func writeFile(_ lines: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-cap-\(UUID().uuidString).csv")
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    return url
  }

  /// Four rows: one normal, two over the cap, and the cap itself. Commit imports
  /// 450.00 and 10^11 paise and skips the other two, with skipped counted; dry run
  /// counts the same two as unreadable. Nothing over the cap reaches the pipeline.
  func testCommitSkipsOverCapRowsAndCountsThemAsSkipped() async throws {
    let url = try writeFile([
      "Date,Narration,Amount",
      "02/11/2026,SWIGGY,450.00",
      "03/11/2026,BIG TRANSFER,1000000000.01",
      "04/11/2026,HUGE,99999999999999999999.00",
      "05/11/2026,CAP,1000000000.00",
    ])
    defer { try? FileManager.default.removeItem(at: url) }
    let ingester = CapturingIngester()
    let service = FileImportServiceImpl(pipeline: ingester)
    let withoutReference = ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
      directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
    )

    let dry = try await service.dryRun(url, mapping: withoutReference)
    XCTAssertEqual(dry.newCount, 2)
    XCTAssertEqual(dry.unreadable.count, 2)

    let summary = try await service.commit(url, mapping: withoutReference, accountID: nil)
    XCTAssertEqual(summary.created + summary.merged, 2)
    XCTAssertEqual(summary.skipped, 2)
    XCTAssertEqual(summary.skipped, dry.unreadable.count)

    let amounts = await ingester.drafts.map(\.amountMinor)
    XCTAssertEqual(amounts, [45_000, AmountRules.maximumMinor])
  }

  /// The PR's fixture table, run end to end: each amount text in a one-row file, through
  /// dry run and commit. An accepted amount is new in dry run and created by commit; a
  /// refused one is unreadable in dry run and skipped by commit (commit throws
  /// `noParseableRows` when no row is left, so that is the refused result).
  func testEachFixtureAmountGivesTheSameVerdictInDryRunAndCommit() async throws {
    let fixtures: [(text: String, accepted: Bool)] = [
      ("1000000000.00", true),
      ("1,00,00,00,000.00", true),
      ("1000000000.01", false),
      ("99999999999999999999.00", false),
      ("-1000000000.00", true),
      ("-1000000000.01", false),
      ("0", false),
      ("0.00", false),
      ("1,234.50", true),
      ("450.555", false),
      ("1.2.3", false),
    ]
    for fixture in fixtures {
      let url = try writeFile([
        "Date,Narration,Amount",
        "02/11/2026,FIXTURE,\(fixture.text)",
      ])
      defer { try? FileManager.default.removeItem(at: url) }
      let ingester = CapturingIngester()
      let service = FileImportServiceImpl(pipeline: ingester)
      let mapping = ColumnMapping(
        dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
        directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
      )

      let dry = try await service.dryRun(url, mapping: mapping)
      let imported: Int
      let skipped: Int
      do {
        let summary = try await service.commit(url, mapping: mapping, accountID: nil)
        imported = summary.created + summary.merged
        skipped = summary.skipped
      } catch ImportError.noParseableRows {
        imported = 0
        skipped = 1
      }

      XCTAssertEqual(dry.newCount, fixture.accepted ? 1 : 0, "\(fixture.text): dry run new")
      XCTAssertEqual(dry.unreadable.count, fixture.accepted ? 0 : 1, "\(fixture.text): dry run unreadable")
      XCTAssertEqual(imported, fixture.accepted ? 1 : 0, "\(fixture.text): commit imported")
      XCTAssertEqual(skipped, fixture.accepted ? 0 : 1, "\(fixture.text): commit skipped")
    }
  }
}
