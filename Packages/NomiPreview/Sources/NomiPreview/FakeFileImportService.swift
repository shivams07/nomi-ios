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

  /// The Import artboard's "Check before importing" numbers (38 to create, 9
  /// matched to rows already in Nomi, none repeated in the file, 2 could not
  /// read) and its three "First rows" lines, so S11's previews match the board.
  /// Fixed, not computed from the URL.
  public func dryRun(_ url: URL, mapping: ColumnMapping) async throws -> ImportDryRun {
    func day(_ day: Int) -> Date {
      NomiCalendar.india.date(from: DateComponents(year: 2026, month: 11, day: day)) ?? .distantPast
    }
    return ImportDryRun(
      createCount: 38,
      matchExistingCount: 9,
      repeatInFileCount: 0,
      unreadable: [
        ["10/11/2026", "CHARGES FOR SMS ALERT", "", "REF020"],
        ["11/11/2026", "REVERSAL HOLD", "", "REF021"],
      ],
      sample: [
        ImportDryRunRow(
          id: 0, date: day(12), descriptionText: "UPI-BIGBASKET-631822904417",
          amountMinor: 201_900, direction: .debit),
        ImportDryRunRow(
          id: 1, date: day(5), descriptionText: "NEFT-ACME PAYROLL SERVICES",
          amountMinor: 3_850_000, direction: .credit),
        ImportDryRunRow(
          id: 2, date: day(4), descriptionText: "UPI-OLACABS-631490022713",
          amountMinor: 31_200, direction: .debit),
      ]
    )
  }

  public func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary {
    // The same split as the fixed dry run above (I-12 Amendment 1).
    ImportSummary(created: 38, merged: 9, skipped: 2, matchedExisting: 9, repeatedInFile: 0)
  }

  public nonisolated func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {}
}
