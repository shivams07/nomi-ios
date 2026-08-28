import NomiCore
import SwiftData

/// Preview-only fixtures for the import flow — same "fresh container per
/// preview" reasoning as `EntryRulesPreviewSupport`, kept local to `Import/**`
/// since this unit must not edit `Entry/**` or `NomiPreview`.
enum ImportPreviewSupport {
  @MainActor
  static func makeAccountContainer() -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Account.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    container.mainContext.insert(NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4821"))
    container.mainContext.insert(NomiCore.Account(displayName: "ICICI Credit Card", institution: "ICICI Bank", lastFour: "9034"))
    return container
  }

  static let detectedPreview = ImportPreview(
    formatSignature: "hdfc-csv-v1",
    detectedBankLabel: "HDFC Bank",
    suggestedMapping: ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: 3,
      directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
    ),
    headers: ["Date", "Narration", "Amount", "Reference"],
    sampleRows: [
      ["01/04/2026", "UPI/P2M/1234/SWIGGY/HDFC/Payment", "-450.00", "REF001"],
      ["02/04/2026", "SALARY CREDIT", "50000.00", "REF002"],
    ],
    parseableRowCount: 41
  )

  static let unknownFormatPreview = ImportPreview(
    formatSignature: "unrecognized-v1",
    detectedBankLabel: nil,
    suggestedMapping: nil,
    headers: ["Column A", "Column B", "Column C"],
    sampleRows: [
      ["01-Apr-2026", "SWIGGY BANGALORE", "450.00"],
    ],
    parseableRowCount: 18
  )
}
