import Foundation
import XCTest
import NomiCore
@testable import NomiUI

/// `TransactionCSVExporter` itself (plain decimal amounts, no ₹, no grouping
/// separator, header row always present) is owned and tested by
/// `NomiCoreTests/Support/TransactionCSVExporterTests.swift` — not this
/// unit's file boundary. What this unit owns is turning that `String` into a
/// file the share sheet can present, which is exercisable with an empty
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

  /// R12b (Y1): each export tap writes its own file, and the share sheet owns
  /// that file until it closes. A second write must not delete the first.
  func testConsecutiveWritesProduceDifferentURLsAndKeepBothFiles() throws {
    let first = try ReportsCSVExport.write([], names: names, periodLabel: "consecutive-test")
    let second = try ReportsCSVExport.write([], names: names, periodLabel: "consecutive-test")
    defer {
      ReportsCSVExport.remove(first)
      ReportsCSVExport.remove(second)
    }

    XCTAssertNotEqual(first, second)
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }

  /// R12b (Y1): the share sheet's dismissal removes exactly the file it showed.
  func testRemoveDeletesOnlyTheGivenFile() throws {
    let first = try ReportsCSVExport.write([], names: names, periodLabel: "remove-test")
    let second = try ReportsCSVExport.write([], names: names, periodLabel: "remove-test")
    defer { ReportsCSVExport.remove(second) }

    ReportsCSVExport.remove(first)

    XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }

  /// R12b (Y1), T2a: clearing the share item (the sheet closing) removes the
  /// file it showed. Kills T2-M11: the setter without its remove line keeps it.
  func testClearingTheShareItemRemovesItsFile() throws {
    let url = try ReportsCSVExport.write([], names: names, periodLabel: "clear-test")
    var state = ReportsShareState()
    state.item = ReportsShareItem(url: url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    state.item = nil

    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertNil(state.item)
  }

  /// Showing a second file removes the first and nothing else.
  func testReplacingTheShareItemRemovesOnlyThePreviousFile() throws {
    let first = try ReportsCSVExport.write([], names: names, periodLabel: "replace-test")
    let second = try ReportsCSVExport.write([], names: names, periodLabel: "replace-test")
    defer { ReportsCSVExport.remove(second) }
    var state = ReportsShareState()
    state.item = ReportsShareItem(url: first)

    state.item = ReportsShareItem(url: second)

    XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }

  func testClearingWithNothingShownLeavesFilesAlone() throws {
    let other = try ReportsCSVExport.write([], names: names, periodLabel: "clear-nothing")
    defer { ReportsCSVExport.remove(other) }
    var state = ReportsShareState()

    state.item = nil

    XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
  }

  /// Re-assigning the item the sheet already shows must not delete its file.
  func testReassigningTheSameItemKeepsItsFile() throws {
    let url = try ReportsCSVExport.write([], names: names, periodLabel: "reassign-test")
    defer { ReportsCSVExport.remove(url) }
    let item = ReportsShareItem(url: url)
    var state = ReportsShareState()
    state.item = item

    state.item = item

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }
}
