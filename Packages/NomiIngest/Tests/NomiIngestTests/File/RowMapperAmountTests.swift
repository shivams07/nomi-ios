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

  /// B7 ruling: one leading "+" is allowed for file import, because some bank exports
  /// write credits as "+1,000.00". A second sign is still refused, whichever it is.
  func testOneLeadingPlusIsReadAndASecondSignIsRefused() {
    XCTAssertEqual(signed("+1,000.00")?.amountMinor, 100_000)
    XCTAssertEqual(signed("+1,000.00")?.direction, .credit)
    XCTAssertNil(signed("+-5"), "a plus then a minus is two signs")
    XCTAssertNil(signed("++5"), "two plus signs")
    XCTAssertNil(signed("+"), "a bare plus is not an amount")
    XCTAssertNil(signed("+1000000000.01"), "the plus does not lift the cap")
    XCTAssertEqual(signed("+1000000000.00")?.amountMinor, AmountRules.maximumMinor)
  }

  // MARK: - Round 3 (Lim FAIL on #209; Andrews rulings)

  private func separate(_ debit: String, _ credit: String) -> ParsedRow? {
    map(["02/11/2026", "PROBE", debit, credit], separateMapping)
  }

  /// `expected` is (paise, direction), or nil for a refused row.
  private func assertSeparate(
    _ debit: String, _ credit: String, _ expected: (Int, Direction)?, _ note: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let label = "debit \"\(debit)\", credit \"\(credit)\" \(note)"
    let row = separate(debit, credit)
    if let expected {
      XCTAssertEqual(row?.amountMinor, expected.0, label, file: file, line: line)
      XCTAssertEqual(row?.direction, expected.1, label, file: file, line: line)
    } else {
      XCTAssertNil(row, label, file: file, line: line)
    }
  }

  /// Ruling 1: only a blank cell, "-", "–" or "—" reads as 0 in a separate-column layout.
  /// Any other non-number refuses the whole row. The other column is never read in its place.
  func testSeparateColumnNonNumberRefusesTheRowNotTheOtherColumn() {
    assertSeparate("1.2.3", "100.00", nil)
    assertSeparate("450 Xr", "100.00", nil, "a suffix that is not on the ruled list")
    assertSeparate("abc", "100.00", nil)
    assertSeparate("", "1.2.3", nil)
  }

  func testOnlyBlankAndDashesReadAsZeroInASeparateColumn() {
    for placeholder in ["", "-", "–", "—"] {
      assertSeparate(placeholder, "100.00", (10_000, .credit))
    }
  }

  /// Ruling 2, separate columns: the suffix must agree with its column.
  func testSuffixMustAgreeWithItsColumn() {
    assertSeparate("450.00 Dr", "", (45_000, .debit))
    assertSeparate("450.00Dr", "", (45_000, .debit))
    assertSeparate("450.00 Dr.", "", (45_000, .debit))
    assertSeparate("450.00 Cr", "", nil)
    assertSeparate("", "100.00 Cr", (10_000, .credit))
    assertSeparate("", "100.00 Dr", nil)
    assertSeparate("450.00 dr", "", (45_000, .debit), "suffixes are case-insensitive (ruling 4)")
    assertSeparate("Dr", "100.00", nil, "a suffix with no number")
  }

  /// Ruling 2, signed column: the suffix sets the direction, and a sign that disagrees with it refuses.
  func testSuffixSetsTheDirectionOnASignedColumn() {
    XCTAssertEqual(signed("1,000.00 Cr")?.amountMinor, 100_000)
    XCTAssertEqual(signed("1,000.00 Cr")?.direction, .credit)
    XCTAssertEqual(signed("450.00 Dr")?.amountMinor, 45_000)
    XCTAssertEqual(signed("450.00 Dr")?.direction, .debit)
    XCTAssertEqual(signed("450.00Dr")?.direction, .debit)
    XCTAssertEqual(signed("450.00 Dr.")?.direction, .debit)
    XCTAssertEqual(signed("450.00 CR")?.direction, .credit)
    XCTAssertEqual(signed("-450.00 Dr")?.amountMinor, 45_000, "a sign that agrees is accepted")
    XCTAssertEqual(signed("-450.00 Dr")?.direction, .debit)
    XCTAssertEqual(signed("+1,000.00 Cr")?.direction, .credit)
  }

  func testSignDisagreeingWithSuffixRefusesTheRow() {
    XCTAssertNil(signed("-450.00 Cr"))
    XCTAssertNil(signed("+450.00 Dr"))
    XCTAssertNil(signed("-1,000.00 Cr"))
  }

  func testSuffixOutsideTheRuledListIsRefused() {
    XCTAssertNil(signed("450.00 Cheque"))
    XCTAssertNil(signed("450.00 D"))
    XCTAssertNil(signed("Dr"))
  }

  /// Ruling 4: Dr and Cr match case-insensitively, with or without a trailing ".".
  func testSuffixIsCaseInsensitive() {
    for spelling in ["dr", "Dr", "DR", "dR"] {
      XCTAssertEqual(signed("450.00 \(spelling)")?.direction, .debit, spelling)
    }
    for spelling in ["cr", "Cr", "CR", "cR"] {
      XCTAssertEqual(signed("450.00 \(spelling)")?.direction, .credit, spelling)
    }
    for spelling in ["dr.", "Dr.", "DR.", "dR."] {
      XCTAssertEqual(signed("450.00 \(spelling)")?.direction, .debit, spelling)
    }
    for spelling in ["cr.", "Cr.", "CR."] {
      XCTAssertEqual(signed("450.00 \(spelling)")?.direction, .credit, spelling)
    }
    XCTAssertEqual(signed("450.00dr")?.direction, .debit)
  }

  /// Ruling 2, flag column: the suffix must agree with the direction the flag gives.
  func testFlagColumnSuffixMustAgreeWithTheFlag() {
    XCTAssertNil(map(["02/11/2026", "TRANSFER", "450.00 Cr", "DEBIT"], flagMapping))
    XCTAssertEqual(map(["02/11/2026", "TRANSFER", "450.00 Dr", "DEBIT"], flagMapping)?.direction, .debit)
  }

  /// Ruling 3: the sign must be adjacent to the number.
  func testSignMustBeAdjacentToTheNumber() {
    XCTAssertNil(signed("+ 5"))
    XCTAssertNil(signed("- 5"))
    assertSeparate("+ 5", "", nil)
  }

  /// Probe rows from Lim's FAIL where the rulings define the outcome. Signed column.
  func testLimSignedProbeRows() {
    XCTAssertEqual(signed("1 000")?.amountMinor, 100_000, "grouping by space, ruled in")
    XCTAssertNil(signed("1e3"), "scientific notation is not manual-entry text")
    XCTAssertEqual(signed("\u{0661}\u{0660}\u{0660}.\u{0660}\u{0660}")?.amountMinor, 10_000, "non-ASCII digits, ruled in")
    XCTAssertEqual(signed(" 450.00 ")?.amountMinor, 45_000)
    XCTAssertNil(signed("-+5"))
    XCTAssertNil(signed("184467440737095516.21"))
    XCTAssertNil(signed("1.2.3"))
    XCTAssertNil(signed("450.555"))
    XCTAssertEqual(signed("+1,000.00")?.amountMinor, 100_000)
  }

  /// Probe rows from Lim's FAIL, separate columns, where the rulings define the outcome.
  func testLimSeparateColumnProbeRows() {
    assertSeparate("450 Dr", "100.00", nil, "both columns non-zero: ambiguous, refused (ruling 1)")
    assertSeparate("450.00 Dr", "", (45_000, .debit), "Lim: correct on main, must stay")
    assertSeparate("", "100.00 Cr", (10_000, .credit))
    assertSeparate("450", "-", (45_000, .debit))
    assertSeparate("+1,000.00", "", (100_000, .debit))
    assertSeparate("(1,000.00)", "", nil)
    assertSeparate("1000000000.01", "450.00", nil)
    assertSeparate("2000000000.00", "500.00", nil)
    assertSeparate("-", "-", nil)
    assertSeparate("", "", nil)
    assertSeparate("450.00 Dr", "100.00 Cr", nil, "both columns non-zero (ruling 1)")
  }

  /// Ruling 1: exactly one column carries a non-zero amount, and it is not negative. A
  /// negative number in either column refuses the row, and so does a non-zero amount in
  /// both (never pick one). Both zero is no amount.
  func testExactlyOneNonZeroNonNegativeAmountPerRow() {
    assertSeparate("450.00", "100.00", nil, "both non-zero")
    assertSeparate("-450.00", "100.00", nil, "negative debit, credit present: refused, not the credit")
    assertSeparate("450.00", "-100.00", nil, "negative credit")
    assertSeparate("-450.00", "", nil, "negative debit alone")
    assertSeparate("", "-100.00", nil, "negative credit alone")
    assertSeparate("-0.00", "", nil, "a negative zero is still negative")
    assertSeparate("", "-0.00", nil, "a negative zero credit")
    assertSeparate("-450.00 Dr", "", nil, "a sign that agrees with the suffix is still negative")
    assertSeparate("0.00", "100.00", (10_000, .credit), "a zero debit is not an amount, so the credit is the one")
    assertSeparate("450.00", "0.00", (45_000, .debit))
    assertSeparate("450.00", "", (45_000, .debit))
    assertSeparate("-", "100.00", (10_000, .credit), "a dash is a placeholder, not a negative")
    assertSeparate("0.00", "0.00", nil, "both zero")
    assertSeparate("0.00", "", nil)
    assertSeparate("", "", nil)
  }

  /// Behaviour change vs main, for review: main read `450.00` beside `100.00` as the debit
  /// (debit wins), and `-450.00` beside `100.00` as the credit. Both now refuse the row.
  func testBothColumnsNonZeroIsNoLongerReadAsTheDebit() {
    XCTAssertNil(map(["02/11/2026", "SWIGGY", "450.00", "100.00"], separateMapping))
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

    // B4b: the dry run asks `simulate`. This double creates every draft, as its
    // `ingest` does, so the dry run's create count is the same meaning it had.
    func simulate(_ batch: [TransactionDraft]) async throws -> IngestBatchResult {
      IngestBatchResult(
        created: batch.count, merged: 0, flagged: 0,
        createdDraftIndexes: Array(batch.indices))
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
    XCTAssertEqual(dry.createCount, 2)
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
      XCTAssertEqual(dry.createCount, fixture.accepted ? 1 : 0, "\(fixture.text): dry run create")
      XCTAssertEqual(dry.unreadable.count, fixture.accepted ? 0 : 1, "\(fixture.text): dry run unreadable")

      // A one-row file with its only row refused has nothing to import, so commit throws
      // `noParseableRows`; it does not return a summary with `skipped` set.
      if fixture.accepted {
        let summary = try await service.commit(url, mapping: mapping, accountID: nil)
        XCTAssertEqual(summary.created + summary.merged, 1, "\(fixture.text): commit imported")
        XCTAssertEqual(summary.skipped, 0, "\(fixture.text): commit skipped")
      } else {
        do {
          _ = try await service.commit(url, mapping: mapping, accountID: nil)
          XCTFail("\(fixture.text): commit must throw noParseableRows for a refused single row")
        } catch ImportError.noParseableRows {
          // Expected.
        }
      }
    }
  }
}
