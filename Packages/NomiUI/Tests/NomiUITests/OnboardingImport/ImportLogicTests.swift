import Foundation
import NomiCore
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

  func testImportPreviewIsEmptyOnlyAtZeroParseableRows() {
    let empty = ImportPreview(formatSignature: "s", detectedBankLabel: nil, suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: 0)
    let nonEmpty = ImportPreview(formatSignature: "s", detectedBankLabel: nil, suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: 1)
    XCTAssertTrue(ImportPreviewSummary.isEmpty(empty))
    XCTAssertFalse(ImportPreviewSummary.isEmpty(nonEmpty))
  }

  func testRowCountTextPluralizesCorrectly() {
    XCTAssertEqual(ImportPreviewSummary.rowCountText(preview(count: 0)), "No transactions found")
    XCTAssertEqual(ImportPreviewSummary.rowCountText(preview(count: 1)), "1 transaction found")
    XCTAssertEqual(ImportPreviewSummary.rowCountText(preview(count: 5)), "5 transactions found")
  }

  private func preview(count: Int) -> ImportPreview {
    ImportPreview(formatSignature: "s", detectedBankLabel: nil, suggestedMapping: nil, headers: [], sampleRows: [], parseableRowCount: count)
  }
}
