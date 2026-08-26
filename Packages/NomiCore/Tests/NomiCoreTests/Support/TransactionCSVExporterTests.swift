import Foundation
import Testing
@testable import NomiCore

struct TransactionCSVExporterTests {
  @Test func rowContainsNoGroupingSeparatorOrRupeeSign() {
    let row = TransactionCSVExporter.row(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "SWIGGY ORDER",
      merchantName: "SWIGGY",
      amountMinor: 123_456,
      directionRaw: Direction.debit.rawValue,
      categoryID: nil,
      accountID: nil
    )
    #expect(!row.contains("₹"))
    #expect(!row.contains("1,234"))
    #expect(row.contains("1234.56"))
  }

  @Test func exportHeaderAlwaysPresentEvenForZeroRows() {
    let csv = TransactionCSVExporter.export([])
    let lines = csv.split(separator: "\n")
    #expect(lines.count == 1)
    #expect(lines[0] == TransactionCSVExporter.header)
  }

  @Test func rowAmountsRoundTripAsParseableDecimals() {
    let rows = [
      TransactionCSVExporter.row(date: Date(), descriptionText: "A", merchantName: nil, amountMinor: 100, directionRaw: Direction.debit.rawValue, categoryID: nil, accountID: nil),
      TransactionCSVExporter.row(date: Date(), descriptionText: "B", merchantName: nil, amountMinor: 50_000, directionRaw: Direction.credit.rawValue, categoryID: nil, accountID: nil),
    ]
    for row in rows {
      let fields = row.split(separator: ",", omittingEmptySubsequences: false)
      let amountField = String(fields[3])
      #expect(Decimal(string: amountField) != nil)
    }
  }

  @Test func negativeAmountFormatsWithLeadingSign() {
    let row = TransactionCSVExporter.row(
      date: Date(),
      descriptionText: "REFUND",
      merchantName: nil,
      amountMinor: -250,
      directionRaw: Direction.credit.rawValue,
      categoryID: nil,
      accountID: nil
    )
    #expect(row.contains(",-2.50,"))
  }
}
