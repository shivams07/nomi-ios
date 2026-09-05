import Foundation
import XCTest
import NomiCore
@testable import NomiUI

/// `TransactionCSVExporter` itself (plain decimal amounts, no ₹, no grouping
/// separator, header row always present) is owned and tested by
/// `NomiCoreTests/Support/TransactionCSVExporterTests.swift` — not this
/// unit's file boundary. What this unit owns is turning that `String` into a
/// file `ShareLink` can present, which is exercisable with an empty
/// `[Transaction]` (same "construct zero, not one" pattern
/// `TransactionCSVExporterTests.exportHeaderAlwaysPresentEvenForZeroRows`
/// already uses) without needing an `@Model` instance under `swift test`.
final class ReportsCSVExportTests: XCTestCase {
  private let names = CSVNameMaps(categories: [:], accounts: [:])

  func testWriteProducesAFileContainingTheHeaderRow() throws {
    let url = try ReportsCSVExport.write([], names: names, periodLabel: "header-test")
    defer { try? FileManager.default.removeItem(at: url) }

    let contents = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(contents.hasPrefix("date,description,merchant,amount,currency,direction,category,account,source,needs_review,merged_count,upi_kind,counterparty_vpa"))
  }

  func testWriteLocatesTheFileInTheTemporaryDirectory() throws {
    let url = try ReportsCSVExport.write([], names: names, periodLabel: "location-test")
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
  }

  func testConsecutiveWritesProduceDifferentURLsAndRemoveThePreviousFile() throws {
    let first = try ReportsCSVExport.write([], names: names, periodLabel: "consecutive-test")
    let second = try ReportsCSVExport.write([], names: names, periodLabel: "consecutive-test")
    defer { try? FileManager.default.removeItem(at: second) }

    XCTAssertNotEqual(first, second)
    XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }
}
