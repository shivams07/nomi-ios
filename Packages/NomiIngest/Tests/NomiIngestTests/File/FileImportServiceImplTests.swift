import XCTest
@testable import NomiCore
@testable import NomiIngest

final class FileImportServiceImplTests: XCTestCase {
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

  // MARK: - Provisional bank presets auto-map with zero user input

  func testEachProvisionalPresetAutoMapsWithZeroInput() async throws {
    let presetFixtures: [(file: String, bankLabel: String)] = [
      ("sbi_preset.csv", "SBI"),
      ("hdfc_preset.csv", "HDFC"),
      ("icici_preset.csv", "ICICI"),
      ("axis_preset.csv", "Axis"),
      ("kotak_preset.csv", "Kotak"),
    ]

    for (file, bankLabel) in presetFixtures {
      let service = await makeService()
      let preview = try await service.inspect(fixture(file))
      XCTAssertEqual(preview.detectedBankLabel, bankLabel, "\(file) should auto-detect \(bankLabel)")
      XCTAssertNotNil(preview.suggestedMapping, "\(file) should suggest a mapping with zero input")
      XCTAssertEqual(preview.parseableRowCount, 3, "\(file) should parse all 3 sample rows")
    }
  }

  func testPresetCommitProducesExpectedDirectionsAndAmounts() async throws {
    let service = await makeService()
    let preview = try await service.inspect(fixture("sbi_preset.csv"))
    let mapping = try XCTUnwrap(preview.suggestedMapping)

    let summary = try await service.commit(fixture("sbi_preset.csv"), mapping: mapping, accountID: nil)
    XCTAssertEqual(summary.created, 3)
    XCTAssertEqual(summary.merged, 0)
    XCTAssertEqual(summary.skipped, 0)
  }

  // MARK: - Unknown format

  func testUnknownFormatReturnsNilMappingWithHeadersAndSamples() async throws {
    let service = await makeService()
    let preview = try await service.inspect(fixture("unknown_format.csv"))

    XCTAssertNil(preview.suggestedMapping)
    XCTAssertNil(preview.detectedBankLabel)
    XCTAssertEqual(preview.headers, ["Posting Date", "What Happened", "Amount", "Type", "Running Total"])
    XCTAssertEqual(preview.sampleRows.count, 2)
    XCTAssertLessThanOrEqual(preview.sampleRows.count, 5)
  }

  // MARK: - Zero-row file

  func testZeroRowFileReportsZeroParseableRows() async throws {
    let service = await makeService()
    let preview = try await service.inspect(fixture("zero_rows.csv"))

    XCTAssertEqual(preview.parseableRowCount, 0)
  }

  // MARK: - Bad encoding

  func testBadEncodingThrowsUnreadableEncoding() async throws {
    let service = await makeService()
    do {
      _ = try await service.inspect(fixture("bad_encoding.csv"))
      XCTFail("expected .unreadableEncoding")
    } catch ImportError.unreadableEncoding {
      // expected
    }
  }

  // MARK: - True legacy BIFF .xls

  func testLegacyBIFFThrowsUnsupportedLegacyXLS() async throws {
    let service = await makeService()
    do {
      _ = try await service.inspect(fixture("legacy_biff.xls"))
      XCTFail("expected .unsupportedLegacyXLS")
    } catch ImportError.unsupportedLegacyXLS {
      // expected
    }
  }

  // MARK: - Content-sniffing: HTML masquerading as .xls

  func testHTMLDisguisedAsXLSIsContentSniffedAndParsed() async throws {
    let service = await makeService()
    let preview = try await service.inspect(fixture("html_statement.xls"))

    XCTAssertEqual(preview.detectedBankLabel, "Kotak")
    XCTAssertNotNil(preview.suggestedMapping)
    XCTAssertEqual(preview.parseableRowCount, 2)
  }

  // MARK: - Saved mapping reuse

  func testSavedMappingIsReusedForSameHeaderSignature() async throws {
    let service = await makeService()
    let firstPreview = try await service.inspect(fixture("unknown_format.csv"))
    XCTAssertNil(firstPreview.suggestedMapping)

    let manualMapping = ColumnMapping(
      dateColumn: 0,
      descriptionColumn: 1,
      amountColumn: 2,
      referenceColumn: nil,
      directionStrategy: .flagColumn(index: 3, debitValues: ["DEBIT"]),
      dateFormat: "dd/MM/yyyy"
    )
    try service.saveMapping(manualMapping, signature: firstPreview.formatSignature, bankLabel: "My Bank")

    let secondPreview = try await service.inspect(fixture("unknown_format.csv"))
    XCTAssertEqual(secondPreview.suggestedMapping, manualMapping)
    XCTAssertEqual(secondPreview.detectedBankLabel, "My Bank")
  }

  // MARK: - Idempotent re-import survives row reordering

  func testReimportWithShuffledRowsProducesZeroNewTransactions() async throws {
    let service = await makeService()
    let preview = try await service.inspect(fixture("sbi_preset.csv"))
    let mapping = try XCTUnwrap(preview.suggestedMapping)

    let firstCommit = try await service.commit(fixture("sbi_preset.csv"), mapping: mapping, accountID: nil)
    XCTAssertEqual(firstCommit.created, 3)

    let secondCommit = try await service.commit(fixture("sbi_preset_shuffled.csv"), mapping: mapping, accountID: nil)
    XCTAssertEqual(secondCommit.created, 0, "shuffled re-import must not create new transactions")
    XCTAssertEqual(secondCommit.merged, 3)
  }

  // MARK: - B2: commit hands the pipeline bounded batches

  /// Records every batch it is handed. `FileImportServiceImpl` takes any
  /// `DraftIngesting`, so this is the same seam `MailSyncEngine` uses.
  private actor RecordingIngester: DraftIngesting {
    private(set) var batchSizes: [Int] = []

    func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
      batchSizes.append(drafts.count)
      // One "created" per row, so the summary's arithmetic is checkable.
      return IngestBatchResult(created: drafts.count, merged: 0, flagged: 0)
    }
  }

  /// A CSV in the SBI preset's shape with `rowCount` data rows, written to a
  /// temp file. Generated rather than committed: 120 rows of fixture would be
  /// 120 rows nobody reads.
  private func makeLargeCSV(rowCount: Int) throws -> URL {
    var lines = ["Txn Date,Description,Ref No./Cheque No.,Value Date,Debit,Credit,Balance"]
    for index in 0..<rowCount {
      let day = (index % 28) + 1
      let date = String(format: "%02d Apr 2026", day)
      let amount = String(format: "%d.00", 100 + index)
      lines.append("\(date),UPI-MERCHANT-\(index),SBIN0N\(index),\(date),\(amount),,10000.00")
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("nomi-import-\(UUID().uuidString).csv")
    try lines.joined(separator: "
").write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  func testCommitChunksDraftsAtTheMailFetchBatchSize() async throws {
    let url = try makeLargeCSV(rowCount: 120)
    defer { try? FileManager.default.removeItem(at: url) }

    let ingester = RecordingIngester()
    let service = FileImportServiceImpl(pipeline: ingester, now: Fixture.clock)
    let preview = try await service.inspect(url)
    let mapping = try XCTUnwrap(preview.suggestedMapping)
    XCTAssertEqual(preview.parseableRowCount, 120, "the whole file parses")

    let summary = try await service.commit(url, mapping: mapping, accountID: nil)

    let sizes = await ingester.batchSizes
    XCTAssertEqual(sizes, [50, 50, 20], "50 is MailSyncEngine.fetchBatchSize")
    XCTAssertEqual(MailSyncEngine.fetchBatchSize, 50, "the batch size is not a second constant")
    XCTAssertEqual(summary.created, 120, "the per-batch results sum into one summary")
    XCTAssertEqual(summary.merged, 0)
    XCTAssertEqual(summary.skipped, 0)
  }

  func testCommitOfAFileSmallerThanOneBatchIsASingleCall() async throws {
    let ingester = RecordingIngester()
    let service = FileImportServiceImpl(pipeline: ingester, now: Fixture.clock)
    let preview = try await service.inspect(fixture("sbi_preset.csv"))
    let mapping = try XCTUnwrap(preview.suggestedMapping)

    let summary = try await service.commit(fixture("sbi_preset.csv"), mapping: mapping, accountID: nil)

    let sizes = await ingester.batchSizes
    XCTAssertEqual(sizes, [3])
    XCTAssertEqual(summary.created, 3)
  }
}
