import Foundation
import XCTest
@testable import NomiCore
@testable import NomiIngest

final class CSVParserTests: XCTestCase {
  private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/File")
      .appendingPathComponent(name)
  }

  private func makeService() async -> FileImportServiceImpl {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    return FileImportServiceImpl(pipeline: pipeline, now: Fixture.clock)
  }

  // MARK: - Line endings

  func testCRLFRowsSplitLikeLF() {
    XCTAssertEqual(CSVParser.parse("a,b\r\nc,d\r\n"), [["a", "b"], ["c", "d"]])
  }

  func testCROnlyRowsSplit() {
    XCTAssertEqual(CSVParser.parse("a,b\rc,d"), [["a", "b"], ["c", "d"]])
  }

  func testMixedEndingsInOneFile() {
    XCTAssertEqual(CSVParser.parse("a\r\nb\nc\rd"), [["a"], ["b"], ["c"], ["d"]])
  }

  func testQuotedCRLFBecomesOneNewline() {
    XCTAssertEqual(CSVParser.parse("\"x\r\ny\",z\r\n"), [["x\ny", "z"]])
  }

  func testQuoteFollowedByCombiningMarkStillCloses() {
    XCTAssertEqual(CSVParser.parse("\"e\u{301}\",1"), [["e\u{301}", "1"]])
  }

  func testBlankCRLFLinesAreDropped() {
    XCTAssertEqual(CSVParser.parse("a\r\n\r\nb\r\n"), [["a"], ["b"]])
  }

  // MARK: - BOM plus CRLF

  func testUTF8BOMPlusCRLFParsesHeaderCleanly() throws {
    let data = Data([0xEF, 0xBB, 0xBF]) + Data("Date,Amount\r\n01/11/2026,10\r\n".utf8)
    let text = try XCTUnwrap(TextDecoder.decode(data))
    let grid = CSVParser.parse(text)
    XCTAssertEqual(grid.first?.first, "Date")
  }

  // MARK: - End to end: a CRLF bank export imports like its LF original

  func testCRLFPresetFileImportsLikeTheLFOriginal() async throws {
    let lfURL = fixture("hdfc_preset.csv")
    let lfData = try Data(contentsOf: lfURL)

    // Rewrite every LF byte as CRLF. Byte-level, so nothing else in the file changes.
    var crlfData = Data()
    for byte in lfData {
      if byte == 0x0A {
        crlfData.append(contentsOf: [0x0D, 0x0A])
      } else {
        crlfData.append(byte)
      }
    }
    let crlfURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-crlf-\(UUID().uuidString).csv")
    try crlfData.write(to: crlfURL)
    defer { try? FileManager.default.removeItem(at: crlfURL) }

    // A fresh service and store per side, so the second commit cannot merge into the first.
    let lfService = await makeService()
    let lfPreview = try await lfService.inspect(lfURL)
    let lfMapping = try XCTUnwrap(lfPreview.suggestedMapping)
    let lfSummary = try await lfService.commit(lfURL, mapping: lfMapping, accountID: nil)

    let crlfService = await makeService()
    let crlfPreview = try await crlfService.inspect(crlfURL)
    let crlfMapping = try XCTUnwrap(crlfPreview.suggestedMapping)
    XCTAssertEqual(crlfPreview.parseableRowCount, lfPreview.parseableRowCount)
    let crlfSummary = try await crlfService.commit(crlfURL, mapping: crlfMapping, accountID: nil)

    XCTAssertGreaterThan(crlfSummary.created, 0)
    XCTAssertEqual(crlfSummary.created, lfSummary.created)
  }
}
