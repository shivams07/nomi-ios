import Foundation
import Testing
@testable import NomiCore

struct TransactionCSVExporterTests {
  @Test func exportContainsNoGroupingSeparatorOrRupeeSign() {
    let transaction = Transaction(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "SWIGGY ORDER",
      merchantName: "SWIGGY",
      normalizedDescription: "SWIGGY ORDER",
      amountMinor: 123_456,
      directionRaw: Direction.debit.rawValue
    )
    let csv = TransactionCSVExporter.export([transaction])
    #expect(!csv.contains("₹"))
    #expect(!csv.contains("1,234"))
    #expect(csv.contains("1234.56"))
  }

  @Test func exportHeaderAlwaysPresentEvenForZeroRows() {
    let csv = TransactionCSVExporter.export([])
    let lines = csv.split(separator: "\n")
    #expect(lines.count == 1)
    #expect(lines[0].hasPrefix("date,description"))
  }

  @Test func exportRoundTripsAmountsAcrossMultipleRows() {
    let transactions = [
      Transaction(date: Date(), descriptionText: "A", normalizedDescription: "A", amountMinor: 100),
      Transaction(date: Date(), descriptionText: "B", normalizedDescription: "B", amountMinor: 50_000),
    ]
    let csv = TransactionCSVExporter.export(transactions)
    let dataLines = csv.split(separator: "\n").dropFirst()
    #expect(dataLines.count == 2)
    for line in dataLines {
      let fields = line.split(separator: ",")
      let amountField = String(fields[3])
      #expect(Decimal(string: amountField) != nil)
    }
  }
}
