import Foundation
import NomiCore
import UniformTypeIdentifiers
import XCTest
@testable import NomiUI

final class ImportLogicTests: XCTestCase {
  func testEveryImportErrorCaseHasDistinctNamedCopy() {
    let messages = [
      ImportErrorMessage.text(for: .unreadableEncoding),
      ImportErrorMessage.text(for: .unsupportedLegacyXLS),
      ImportErrorMessage.text(for: .malformedStructure(reason: "row 4 is short")),
      ImportErrorMessage.text(for: .noParseableRows),
    ]
    XCTAssertEqual(Set(messages).count, messages.count)
    for message in messages {
      XCTAssertFalse(message.isEmpty)
    }
  }

  func testMalformedStructureIncludesReason() {
    XCTAssertTrue(ImportErrorMessage.text(for: .malformedStructure(reason: "row 4 is short")).contains("row 4 is short"))
  }

  private let headers = ["Date", "Narration", "Amount", "Reference"]

  private func mapping(
    date: Int = 0, description: Int = 1, amount: Int = 2, reference: Int? = 3,
    strategy: DirectionStrategy = .signedAmount
  ) -> ColumnMapping {
    ColumnMapping(dateColumn: date, descriptionColumn: description, amountColumn: amount, referenceColumn: reference, directionStrategy: strategy, dateFormat: "dd/MM/yyyy")
  }

  func testMappingValidWhenAllColumnsInBoundsAndDistinct() {
    XCTAssertTrue(ColumnMappingFormGate.isValid(mapping(), headerCount: headers.count))
  }

  func testMappingInvalidWhenColumnOutOfBounds() {
    XCTAssertFalse(ColumnMappingFormGate.isValid(mapping(amount: 9), headerCount: headers.count))
  }

  func testMappingInvalidWhenRequiredColumnsCollide() {
    XCTAssertFalse(ColumnMappingFormGate.isValid(mapping(description: 0), headerCount: headers.count))
  }

  func testMappingValidWithoutOptionalReferenceColumn() {
    XCTAssertTrue(ColumnMappingFormGate.isValid(mapping(reference: nil), headerCount: headers.count))
  }

  func testMappingInvalidWhenSeparateColumnsCollide() {
    let strategy = DirectionStrategy.separateColumns(debit: 2, credit: 2)
    XCTAssertFalse(ColumnMappingFormGate.isValid(mapping(strategy: strategy), headerCount: headers.count))
  }

  func testMappingValidWithDistinctSeparateColumns() {
    let strategy = DirectionStrategy.separateColumns(debit: 2, credit: 3)
    XCTAssertTrue(ColumnMappingFormGate.isValid(mapping(reference: nil, strategy: strategy), headerCount: headers.count))
  }

  func testMappingInvalidWhenFlagColumnHasNoDebitValues() {
    let strategy = DirectionStrategy.flagColumn(index: 2, debitValues: [])
    XCTAssertFalse(ColumnMappingFormGate.isValid(mapping(strategy: strategy), headerCount: headers.count))
  }

  func testMappingValidWithFlagColumnAndDebitValues() {
    let strategy = DirectionStrategy.flagColumn(index: 2, debitValues: ["DR"])
    XCTAssertTrue(ColumnMappingFormGate.isValid(mapping(strategy: strategy), headerCount: headers.count))
  }

  // finding 5: saveMapping was called with the imported file's
  // `url.lastPathComponent` instead of `preview.formatSignature`. A file
  // named "statement (1).csv" and a re-download named "statement (2).csv"
  // are the same bank format with two different names — the saved key must
  // track the format, not the name.
  func testSavedMappingKeySignatureIsThePreviewsFormatSignatureNotAFileName() {
    let preview = ImportPreview(
      formatSignature: "col-sig-3f9a", detectedBankLabel: "HDFC Bank",
      suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: 1
    )
    let key = SavedMappingKey.make(from: preview)
    XCTAssertEqual(key.signature, preview.formatSignature)
    XCTAssertNotEqual(key.signature, "statement (2).csv")
  }

  func testSavedMappingKeyUsesDetectedBankLabelWhenPresent() {
    let preview = ImportPreview(
      formatSignature: "col-sig-3f9a", detectedBankLabel: "HDFC Bank",
      suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: 1
    )
    XCTAssertEqual(SavedMappingKey.make(from: preview).bankLabel, "HDFC Bank")
  }

  func testSavedMappingKeyFallsBackToSignatureWhenNoBankLabelDetected() {
    let preview = ImportPreview(
      formatSignature: "col-sig-3f9a", detectedBankLabel: nil,
      suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: 1
    )
    XCTAssertEqual(SavedMappingKey.make(from: preview).bankLabel, "col-sig-3f9a")
  }

  // MARK: - M5: the picker's allow-list

  func testAllowedFileTypesConformXLSByExtension() {
    let xls = UTType(filenameExtension: "xls")!
    XCTAssertTrue(ImportFileTypes.allowed.contains { xls.conforms(to: $0) })
  }

  func testAllowedFileTypesConformHTMLByExtension() {
    let html = UTType(filenameExtension: "html")!
    XCTAssertTrue(ImportFileTypes.allowed.contains { html.conforms(to: $0) })
  }

  // MARK: - IM: done-state copy (ImportDone artboard)

  /// The nine title cases from the ruling: created 0, 1 and many, against
  /// skipped 0, 1 and many. `merged` does not affect the title.
  func testDoneTitleTable() {
    let cases: [(created: Int, skipped: Int, expected: String)] = [
      (0, 0, "No new transactions"),
      (0, 1, "No new transactions, 1 skipped"),
      (0, 2, "No new transactions, 2 skipped"),
      (1, 0, "1 transaction imported"),
      (1, 1, "1 transaction imported, 1 skipped"),
      (1, 2, "1 transaction imported, 2 skipped"),
      (24, 0, "24 transactions imported"),
      (24, 1, "24 transactions imported, 1 skipped"),
      (24, 2, "24 transactions imported, 2 skipped"),
    ]
    for testCase in cases {
      let summary = ImportSummary(created: testCase.created, merged: 0, skipped: testCase.skipped)
      XCTAssertEqual(
        ImportDoneCopy.title(summary), testCase.expected,
        "created \(testCase.created), skipped \(testCase.skipped)")
    }
  }

  func testDoneDetailNamesTheAccount() {
    let summary = ImportSummary(created: 24, merged: 0, skipped: 2)
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: "HDFC Savings"), "HDFC Savings")
  }

  func testDoneDetailCountsOneMatchAfterTheAccount() {
    let summary = ImportSummary(created: 5, merged: 1, skipped: 0)
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: "HDFC Savings"), "HDFC Savings · 1 matched an existing transaction")
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: nil), "1 matched an existing transaction")
  }

  func testDoneDetailCountsManyMatchesAfterTheAccount() {
    let summary = ImportSummary(created: 5, merged: 3, skipped: 0)
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: "HDFC Savings"), "HDFC Savings · 3 matched existing transactions")
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: nil), "3 matched existing transactions")
  }

  /// The re-import case: every parsed row matched, so nothing was created.
  func testDoneDetailForAReimportNamesTheAccountAndAllMatches() {
    let summary = ImportSummary(created: 0, merged: 24, skipped: 0)
    XCTAssertEqual(ImportDoneCopy.detail(summary, accountName: "HDFC Savings"), "HDFC Savings · 24 matched existing transactions")
    XCTAssertEqual(ImportDoneCopy.title(summary), "No new transactions")
  }

  func testDoneDetailIsNilWhenThereIsNothingToSay() {
    let summary = ImportSummary(created: 24, merged: 0, skipped: 2)
    XCTAssertNil(ImportDoneCopy.detail(summary, accountName: nil))
  }

  func testDoneDetailIgnoresAnEmptyAccountName() {
    let summary = ImportSummary(created: 24, merged: 0, skipped: 2)
    XCTAssertNil(ImportDoneCopy.detail(summary, accountName: ""))
  }

  // MARK: - UF1: column-mapping sheet close (Cancel discards, Save writes back)

  private let closeHeaders = 4

  private var validDraft: ColumnMapping {
    mapping(date: 0, description: 1, amount: 2, reference: nil)
  }

  /// A draft that differs from the original in one column, so a write-back
  /// is visible by value.
  private var editedDraft: ColumnMapping {
    mapping(date: 0, description: 1, amount: 3, reference: nil)
  }

  func testCancelWritesNothingBackEvenWithAnEditedDraft() {
    XCTAssertNil(
      ColumnMappingSheetOutcome.writeBack(.cancel, draft: editedDraft, headerCount: closeHeaders),
      "Cancel discards the draft: the binding keeps its original value")
  }

  func testCancelWritesNothingBackEvenWithAValidDraft() {
    XCTAssertNil(ColumnMappingSheetOutcome.writeBack(.cancel, draft: validDraft, headerCount: closeHeaders))
  }

  func testSaveWritesTheValidDraftBack() {
    XCTAssertEqual(
      ColumnMappingSheetOutcome.writeBack(.save, draft: editedDraft, headerCount: closeHeaders), editedDraft)
  }

  /// The Save button is disabled on this gate, so an invalid draft is never
  /// written. The pure type refuses it too, rather than trusting the button.
  func testSaveWritesNothingBackForAnInvalidDraft() {
    let outOfBounds = mapping(date: 0, description: 1, amount: 9, reference: nil)
    XCTAssertNil(ColumnMappingSheetOutcome.writeBack(.save, draft: outOfBounds, headerCount: closeHeaders))
  }

  // MARK: - S11: the check screen's copy and gates

  /// The primary button's count is a catalog plural: "Import 1 transaction", not "1 transactions".
  func testImportTitleUsesCatalogPluralsForZeroOneAndTwo() {
    XCTAssertEqual(ImportLogic.importTitle(newCount: 0), "Import 0 transactions")
    XCTAssertEqual(ImportLogic.importTitle(newCount: 1), "Import 1 transaction")
    XCTAssertEqual(ImportLogic.importTitle(newCount: 2), "Import 2 transactions")
  }

  func testSkippedNoteUsesCatalogPluralsForOneAndTwo() {
    XCTAssertEqual(ImportLogic.skippedNote(count: 1), "1 row could not be read and will be skipped.")
    XCTAssertEqual(ImportLogic.skippedNote(count: 2), "2 rows could not be read and will be skipped.")
  }

  /// I-12: a stated zero never offers Import, and nothing is counted as new when nothing is new.
  func testImportIsOfferedOnlyWhenSomethingIsNew() {
    XCTAssertFalse(ImportLogic.canImport(newCount: 0))
    XCTAssertTrue(ImportLogic.canImport(newCount: 1))
  }

  func testFileSubtitleNamesTheFormatAndTheSampleRange() {
    let rows = [
      Self.dryRunRow(id: 0, day: 12),
      Self.dryRunRow(id: 1, day: 5),
      Self.dryRunRow(id: 2, day: 4),
    ]
    XCTAssertEqual(
      ImportLogic.fileSubtitle(bankLabel: "HDFC Bank", sample: rows),
      "HDFC Bank format · 4 Nov to 12 Nov"
    )
  }

  func testFileSubtitleWithoutABankSaysUnrecognizedFormat() {
    XCTAssertEqual(
      ImportLogic.fileSubtitle(bankLabel: nil, sample: [Self.dryRunRow(id: 0, day: 3)]),
      "Unrecognized format · 3 Nov to 3 Nov"
    )
  }

  func testFileSubtitleOmitsTheRangeWhenThereIsNoSample() {
    XCTAssertEqual(ImportLogic.fileSubtitle(bankLabel: "HDFC Bank", sample: []), "HDFC Bank format")
  }

  /// "Show them" lists each unreadable row's raw cells. Empty cells are dropped, not drawn as "· ·".
  func testRawRowSkipsEmptyCells() {
    XCTAssertEqual(
      ImportSampleRow.text(["03/11/2026", "NEFT SALARY ACME", "", "50000.00", "60000.00"]),
      "03/11/2026 · NEFT SALARY ACME · 50000.00 · 60000.00"
    )
  }

  func testRawRowSkipsWhitespaceOnlyCells() {
    XCTAssertEqual(ImportSampleRow.text(["05/11/2026", "   ", "320.00", ""]), "05/11/2026 · 320.00")
  }

  func testRawRowOfOnlyEmptyCellsIsEmpty() {
    XCTAssertEqual(ImportSampleRow.text(["", " ", ""]), "")
  }

  func testRawRowKeepsEveryFilledCellInOrder() {
    XCTAssertEqual(ImportSampleRow.text(["a", "b", "c"]), "a · b · c")
  }

  /// A file row with no narration has no title to show. "Manual entry", the row
  /// fallback on the ledger, would say the user typed it, which is false for an import.
  func testSampleTitleOfABlankNarrationIsNotManualEntry() {
    XCTAssertEqual(ImportLogic.sampleTitle(Self.dryRunRow(id: 0, day: 3, text: "   ")), "No narration")
    XCTAssertEqual(ImportLogic.sampleTitle(Self.dryRunRow(id: 0, day: 3, text: " SALARY ")), "SALARY")
  }

  private static func dryRunRow(id: Int, day: Int, text: String = "UPI-BIGBASKET-631822904417") -> ImportDryRunRow {
    ImportDryRunRow(
      id: id,
      date: NomiCalendar.india.date(from: DateComponents(year: 2026, month: 11, day: day)) ?? .distantPast,
      descriptionText: text,
      amountMinor: 201_900,
      direction: .debit
    )
  }
}
