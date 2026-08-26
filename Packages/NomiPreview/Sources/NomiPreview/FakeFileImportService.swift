import Foundation
import NomiCore

public actor FakeFileImportService: FileImportService {
  public init() {}

  public func inspect(_ url: URL) async throws -> ImportPreview {
    ImportPreview(
      formatSignature: "preview-signature",
      detectedBankLabel: "HDFC Bank",
      suggestedMapping: ColumnMapping(
        dateColumn: 0,
        descriptionColumn: 1,
        amountColumn: 2,
        referenceColumn: 3,
        directionStrategy: .signedAmount,
        dateFormat: "dd/MM/yyyy"
      ),
      headers: ["Date", "Narration", "Amount", "Reference"],
      sampleRows: [
        ["01/04/2026", "UPI/P2M/1234/SWIGGY/HDFC/Payment", "-450.00", "REF001"],
        ["02/04/2026", "SALARY CREDIT", "50000.00", "REF002"],
      ],
      parseableRowCount: 2
    )
  }

  public func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary {
    ImportSummary(created: 2, merged: 0, skipped: 0)
  }

  public func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {}
}
