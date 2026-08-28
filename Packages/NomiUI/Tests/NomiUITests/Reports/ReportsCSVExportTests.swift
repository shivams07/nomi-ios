import Foundation
import XCTest
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
  func testWriteProducesAFileContainingTheHeaderRow() throws {
    let url = try ReportsCSVExport.write([], filename: "reports-export-test.csv")
    defer { try? FileManager.default.removeItem(at: url) }

    let contents = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(contents.hasPrefix("date,description,merchant,amount,direction,category_id,account_id"))
  }

  func testWriteUsesTheRequestedFilename() throws {
    let url = try ReportsCSVExport.write([], filename: "custom-name.csv")
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertEqual(url.lastPathComponent, "custom-name.csv")
  }

  func testWriteLocatesTheFileInTheTemporaryDirectory() throws {
    let url = try ReportsCSVExport.write([], filename: "reports-export-location-test.csv")
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
  }
}
