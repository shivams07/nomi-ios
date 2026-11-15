import Foundation
import NomiCore
import NomiPreview
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

  /// A check screen seeded in `state`. The file URL is preview-only.
  @MainActor
  static func check(_ state: ImportCheckState) -> ImportCheckModel {
    ImportCheckModel(service: FakeFileImportService(), url: URL(fileURLWithPath: "statement-nov.csv"), seed: state)
  }

  static let detectedPreview = ImportPreview(
    formatSignature: "hdfc-csv-v1",
    detectedBankLabel: "HDFC Bank",
    suggestedMapping: detectedMapping,
    headers: ["Date", "Narration", "Amount", "Reference"],
    sampleRows: [
      ["01/04/2026", "UPI/P2M/1234/SWIGGY/HDFC/Payment", "-450.00", "REF001"],
      ["02/04/2026", "SALARY CREDIT", "50000.00", "REF002"],
    ],
    parseableRowCount: 41
  )

  static let detectedMapping = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: 3,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
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

  /// The check screen's numbers (38 new, 9 already in Nomi, 2 could not read) and its
  /// three sample rows. They match `FakeFileImportService.dryRun`, so the previews
  /// show the same numbers as the board.
  static let readyCounts = ImportDryRun(
    newCount: 38,
    alreadyImportedCount: 9,
    unreadable: [
      ["10/11/2026", "CHARGES FOR SMS ALERT", "", "REF020"],
      ["11/11/2026", "REVERSAL HOLD", "", "REF021"],
    ],
    sample: [
      ImportDryRunRow(
        id: 0, date: previewDay(12), descriptionText: "UPI-BIGBASKET-631822904417",
        amountMinor: 201_900, direction: .debit),
      ImportDryRunRow(
        id: 1, date: previewDay(5), descriptionText: "NEFT-ACME PAYROLL SERVICES",
        amountMinor: 3_850_000, direction: .credit),
      ImportDryRunRow(
        id: 2, date: previewDay(4), descriptionText: "UPI-OLACABS-631490022713",
        amountMinor: 31_200, direction: .debit),
    ]
  )

  /// Every row unreadable: Import is off and the mapping is the way out.
  static let unreadableOnlyCounts = ImportDryRun(
    newCount: 0,
    alreadyImportedCount: 0,
    unreadable: [
      ["01-Apr-2026", "SWIGGY BANGALORE", "450.00"],
      ["02-Apr-2026", "AMAZON PAY", "320.00"],
    ],
    sample: []
  )

  private static func previewDay(_ day: Int) -> Date {
    NomiCalendar.india.date(from: DateComponents(year: 2026, month: 11, day: day)) ?? .distantPast
  }
}
