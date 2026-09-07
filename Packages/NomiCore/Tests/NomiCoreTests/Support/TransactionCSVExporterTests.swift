import Foundation
import Testing
@testable import NomiCore

struct TransactionCSVExporterTests {
  private static let categoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
  private static let unknownID = UUID(uuidString: "00000000-0000-0000-0000-000000000703")!

  private func row(
    descriptionText: String = "SWIGGY ORDER",
    merchantName: String? = "SWIGGY",
    amountMinor: Int = 123_456,
    currencyCode: String = "INR",
    directionRaw: String = Direction.debit.rawValue,
    categoryName: String = "",
    accountName: String = "",
    sourceRaw: String = IngestSource.manual.rawValue,
    needsReview: Bool = false,
    mergedCount: Int = 1,
    upiKindRaw: String? = nil,
    counterpartyVPA: String? = nil,
    note: String? = nil
  ) -> String {
    TransactionCSVExporter.row(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: descriptionText,
      merchantName: merchantName,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      directionRaw: directionRaw,
      categoryName: categoryName,
      accountName: accountName,
      sourceRaw: sourceRaw,
      needsReview: needsReview,
      mergedCount: mergedCount,
      upiKindRaw: upiKindRaw,
      counterpartyVPA: counterpartyVPA,
      note: note
    )
  }

  @Test func rowContainsNoGroupingSeparatorOrRupeeSign() {
    let csvRow = row(amountMinor: 123_456)
    #expect(!csvRow.contains("₹"))
    #expect(!csvRow.contains("1,234"))
    #expect(csvRow.contains("1234.56"))
  }

  @Test func exportHeaderAlwaysPresentEvenForZeroRows() {
    let csv = TransactionCSVExporter.export([], names: CSVNameMaps(categories: [:], accounts: [:]))
    let lines = csv.split(separator: "\n")
    #expect(lines.count == 1)
    #expect(lines[0] == TransactionCSVExporter.header)
  }

  @Test func headerIsExactlyTheFourteenColumns() {
    #expect(TransactionCSVExporter.header == "date,description,merchant,amount,currency,direction,category,account,source,needs_review,merged_count,upi_kind,counterparty_vpa,note")
  }

  @Test func rowAmountsRoundTripAsParseableDecimals() {
    let csvRows = [row(amountMinor: 100), row(amountMinor: 50_000)]
    for csvRow in csvRows {
      let fields = csvRow.split(separator: ",", omittingEmptySubsequences: false)
      let amountField = String(fields[3])
      #expect(Decimal(string: amountField) != nil)
    }
  }

  @Test func negativeAmountIsNotPrefixed() {
    let csvRow = row(descriptionText: "REFUND", amountMinor: -250)
    #expect(csvRow.contains(",-2.50,"))
    #expect(!csvRow.contains("'-2.50"))
  }

  @Test func descriptionStartingWithEqualsIsPrefixedForFormulaInjection() {
    let csvRow = row(descriptionText: "=HYPERLINK(evil.com)")
    let fields = csvRow.split(separator: ",", omittingEmptySubsequences: false)
    #expect(String(fields[1]) == "'=HYPERLINK(evil.com)")
  }

  @Test func descriptionStartingWithPlusIsPrefixed() {
    let csvRow = row(descriptionText: "+919999999999")
    let fields = csvRow.split(separator: ",", omittingEmptySubsequences: false)
    #expect(String(fields[1]) == "'+919999999999")
  }

  @Test func counterpartyVPAStartingWithAtIsPrefixed() {
    let csvRow = row(counterpartyVPA: "@upi")
    #expect(csvRow.hasSuffix(",'@upi,"))
  }

  @Test func ordinaryCommaContainingDescriptionIsQuotedButNotPrefixed() {
    let csvRow = row(descriptionText: "Swiggy, Koramangala")
    #expect(csvRow.contains("\"Swiggy, Koramangala\""))
    #expect(!csvRow.contains("'Swiggy"))
  }

  @Test func categoryAndAccountColumnsCarryNamesOrEmptyForUnknownID() {
    let names: [UUID: String] = [Self.categoryID: "Food & Dining"]
    #expect(TransactionCSVExporter.resolvedName(for: Self.categoryID, in: names) == "Food & Dining")
    #expect(TransactionCSVExporter.resolvedName(for: Self.unknownID, in: names) == "")
    #expect(TransactionCSVExporter.resolvedName(for: nil, in: names) == "")
  }

  @Test func rowCarriesResolvedCategoryAndAccountNames() {
    let csvRow = row(categoryName: "Food & Dining", accountName: "HDFC Savings")
    #expect(csvRow.contains(",Food & Dining,HDFC Savings,"))
  }

  @Test func rowCarriesNoteAsTheLastColumn() {
    let csvRow = row(note: "Split with roommate")
    #expect(csvRow.hasSuffix(",Split with roommate"))
  }

  @Test func rowWithNoNoteHasAnEmptyLastColumn() {
    let csvRow = row(note: nil)
    #expect(csvRow.hasSuffix(","))
  }

  @Test func noteContainingACommaIsQuoted() {
    let csvRow = row(note: "Great, thanks")
    #expect(csvRow.hasSuffix("\"Great, thanks\""))
  }
}
