import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// Scripted stand-in for `FileImportServiceImpl`. Every call is counted, so a test
/// can assert what did and did not run. It conforms to `FileImportService` itself
/// because `FakeFileImportService` is an actor and cannot be subclassed.
final class ImportCheckSpy: FileImportService, @unchecked Sendable {
  typealias Inspect = @Sendable () throws -> ImportPreview
  typealias DryRun = @Sendable (ColumnMapping) async throws -> ImportDryRun
  typealias Commit = @Sendable () async throws -> ImportSummary

  private let lock = NSLock()
  private let inspectScript: Inspect
  private let dryRunScript: DryRun
  private let commitScript: Commit
  private var dryRunMappings: [ColumnMapping] = []
  private var commitCalls = 0
  private var saves: [(signature: String, bankLabel: String)] = []

  init(inspect: @escaping Inspect, dryRun: @escaping DryRun, commit: @escaping Commit = { ImportSummary(created: 0, merged: 0, skipped: 0) }) {
    self.inspectScript = inspect
    self.dryRunScript = dryRun
    self.commitScript = commit
  }

  var dryRunCount: Int { lock.withLock { dryRunMappings.count } }
  var commitCount: Int { lock.withLock { commitCalls } }
  var saveCount: Int { lock.withLock { saves.count } }
  var savedSignatures: [String] { lock.withLock { saves.map(\.signature) } }
  var savedBankLabels: [String] { lock.withLock { saves.map(\.bankLabel) } }

  func inspect(_ url: URL) async throws -> ImportPreview {
    try inspectScript()
  }

  func dryRun(_ url: URL, mapping: ColumnMapping) async throws -> ImportDryRun {
    lock.withLock { dryRunMappings.append(mapping) }
    return try await dryRunScript(mapping)
  }

  func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary {
    lock.withLock { commitCalls += 1 }
    return try await commitScript()
  }

  func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {
    lock.withLock { saves.append((signature: signature, bankLabel: bankLabel)) }
  }
}

/// Counts attempts from inside a scripted closure.
private final class AttemptCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// Returns the attempt number, starting at 1.
  func next() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

private struct SpyFailure: Error {}

@MainActor
final class ImportCheckModelTests: XCTestCase {
  // Fixtures are Sendable values, so they are nonisolated: the scripted closures run off the main actor.
  nonisolated private static let url = URL(fileURLWithPath: "statement-nov.csv")
  nonisolated private static let headers = ["Date", "Narration", "Withdrawal Amt.", "Deposit Amt.", "Closing Balance"]
  nonisolated private static let saved = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )

  /// A preview with a mapping the format recognised, or without one (needs columns).
  nonisolated private static func preview(suggested: ColumnMapping?) -> ImportPreview {
    ImportPreview(
      formatSignature: "statement-nov-sig",
      detectedBankLabel: suggested == nil ? nil : "HDFC Bank",
      suggestedMapping: suggested,
      headers: headers,
      sampleRows: [],
      parseableRowCount: suggested == nil ? 0 : 3
    )
  }

  nonisolated private static func counts(new: Int, already: Int = 0, unreadable: Int = 0) -> ImportDryRun {
    ImportDryRun(
      newCount: new,
      alreadyImportedCount: already,
      unreadable: Array(repeating: ["", "UPI-SWIGGY", "", "REF9"], count: unreadable),
      sample: []
    )
  }

  // MARK: - Loading and the first count

  func testKnownFormatGoesStraightToReady() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: Self.saved) },
      dryRun: { _ in Self.counts(new: 38, already: 9, unreadable: 2) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)

    await model.load()

    guard case .ready(_, let dry, _) = model.state else {
      return XCTFail("a format with a suggested mapping goes straight to the check, got \(model.state)")
    }
    XCTAssertEqual(dry.newCount, 38)
    XCTAssertEqual(dry.alreadyImportedCount, 9)
    XCTAssertEqual(dry.unreadable.count, 2)
    XCTAssertEqual(spy.dryRunCount, 1)
  }

  func testUnknownFormatNeedsColumnsFirst() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { _ in Self.counts(new: 5) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)

    await model.load()

    guard case .needsColumns = model.state else {
      return XCTFail("a file with no suggested mapping must open the column mapping first, got \(model.state)")
    }
    XCTAssertEqual(spy.dryRunCount, 0, "nothing is counted until a mapping exists")
  }

  // MARK: - D13: the count shown is the dry run's count under the mapping

  func testCountAfterMappingIsTheDryRunCount() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { mapping in Self.counts(new: mapping == Self.saved ? 3 : 0) },
      commit: { ImportSummary(created: 3, merged: 0, skipped: 0) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()

    await model.applyMapping(Self.saved)

    guard case .ready(_, let dry, let mapping) = model.state else {
      return XCTFail("a mapping that parses rows lands on the check, got \(model.state)")
    }
    XCTAssertEqual(dry.newCount, 3)
    XCTAssertEqual(mapping, Self.saved, "the sheet's mapping is the one the count used")
    XCTAssertFalse(model.isCounting)
  }

  func testCountAgreesWithWhatTheCommitDoes() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: Self.saved) },
      dryRun: { _ in Self.counts(new: 4, already: 2) },
      commit: { ImportSummary(created: 3, merged: 3, skipped: 0) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()
    guard case .ready(_, let dry, _) = model.state else { return XCTFail("expected ready") }

    await model.importNow(accountID: nil)

    guard case .done(let summary) = model.state else {
      return XCTFail("a successful commit ends on the Done screen, got \(model.state)")
    }
    // The dry run's new count can differ from created: an in-file duplicate folds
    // into an earlier row and lands in merged. What must hold is that every parsed
    // row is accounted for once (I-12's invariant).
    XCTAssertEqual(dry.newCount + dry.alreadyImportedCount, summary.created + summary.merged)
  }

  // MARK: - Saving the mapping happens only after a commit

  func testApplyingAMappingDoesNotSaveIt() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { _ in Self.counts(new: 3) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()

    await model.applyMapping(Self.saved)

    guard case .ready = model.state else {
      return XCTFail("the mapping must be counted before the no-save check means anything, got \(model.state)")
    }
    XCTAssertEqual(spy.saveCount, 0)
  }

  func testMappingSavedOnlyAfterCommitSucceeds() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { _ in Self.counts(new: 3) },
      commit: { throw ImportError.malformedStructure(reason: "column count changes after row 12") }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()
    await model.applyMapping(Self.saved)

    await model.importNow(accountID: nil)

    XCTAssertEqual(spy.commitCount, 1)
    XCTAssertEqual(spy.saveCount, 0, "a commit that throws must never save the mapping")
    XCTAssertNotNil(model.commitNote, "the failure is named on the check screen")
    guard case .ready(_, let dry, _) = model.state else {
      return XCTFail("a failed commit keeps the check on screen, got \(model.state)")
    }
    XCTAssertEqual(dry.newCount, 3, "the counts stay on screen after a failed commit")
  }

  func testMappingSavedAfterASuccessfulCommit() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { _ in Self.counts(new: 3) },
      commit: { ImportSummary(created: 3, merged: 0, skipped: 0) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()
    await model.applyMapping(Self.saved)

    await model.importNow(accountID: nil)

    XCTAssertEqual(spy.saveCount, 1)
    XCTAssertEqual(spy.savedSignatures, ["statement-nov-sig"], "saved under the file's format signature")
    XCTAssertEqual(spy.savedBankLabels, ["statement-nov-sig"], "no bank detected, so the signature is the label")
    XCTAssertNil(model.commitNote)
  }

  // MARK: - Zero new rows and failures

  func testZeroNewDisablesImport() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: Self.saved) },
      dryRun: { _ in Self.counts(new: 0, already: 9) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()

    await model.importNow(accountID: nil)

    XCTAssertEqual(spy.commitCount, 0, "nothing new means Import never reaches commit")
    guard case .ready = model.state else {
      return XCTFail("a zero-new count stays on the check with Import off, got \(model.state)")
    }
  }

  func testImportIsRefusedWhileTheMappingIsStillNeeded() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { _ in Self.counts(new: 3) }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()
    guard case .needsColumns = model.state else {
      return XCTFail("the file must be waiting for columns before Import is tried, got \(model.state)")
    }

    await model.importNow(accountID: nil)

    XCTAssertEqual(spy.commitCount, 0)
    guard case .needsColumns = model.state else {
      return XCTFail("Import must not move the screen on, got \(model.state)")
    }
  }

  func testDryRunFailureIsAFailedStateNeverAZero() async {
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: Self.saved) },
      dryRun: { _ in throw SpyFailure() }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)

    await model.load()

    guard case .failed(let message) = model.state else {
      return XCTFail("a lookup that throws must show the failed state, got \(model.state)")
    }
    XCTAssertEqual(message, "Couldn’t read this file. Nothing was imported.")
  }

  func testRetryAfterAFailedCountCountsAgain() async {
    let attempts = AttemptCounter()
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: Self.saved) },
      dryRun: { _ in
        if attempts.next() == 1 { throw SpyFailure() }
        return Self.counts(new: 38, already: 9)
      }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()
    guard case .failed = model.state else { return XCTFail("the first count should fail") }

    await model.retry()

    guard case .ready(_, let dry, _) = model.state else {
      return XCTFail("Try again must count the file again, got \(model.state)")
    }
    XCTAssertEqual(dry.newCount, 38)
  }

  /// A count for an earlier mapping that finishes after a newer one must not
  /// overwrite the newer counts. The first count is held for 300 ms; the second
  /// starts 50 ms in and returns at once.
  func testStaleCountDoesNotOverwriteANewerMapping() async throws {
    let first = ImportCheckMapping.first
    let second = ImportCheckMapping.second
    let spy = ImportCheckSpy(
      inspect: { Self.preview(suggested: nil) },
      dryRun: { mapping in
        if mapping == first {
          try await Task.sleep(nanoseconds: 300_000_000)
          return Self.counts(new: 1)
        }
        return Self.counts(new: 5)
      }
    )
    let model = ImportCheckModel(service: spy, url: Self.url)
    await model.load()

    let held = Task { await model.applyMapping(first) }
    try await Task.sleep(nanoseconds: 50_000_000)
    await model.applyMapping(second)
    _ = try await withTestTimeout(seconds: 5) { await held.value }

    guard case .ready(_, let dry, let mapping) = model.state else {
      return XCTFail("expected the newer mapping's counts, got \(model.state)")
    }
    XCTAssertEqual(mapping, second)
    XCTAssertEqual(dry.newCount, 5, "the late count for the first mapping must not win")
    XCTAssertFalse(model.isCounting)
  }
}

/// Two mappings that differ only in the amount column, for the stale-count test.
private enum ImportCheckMapping {
  static let first = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )
  static let second = ColumnMapping(
    dateColumn: 0, descriptionColumn: 1, amountColumn: 3, referenceColumn: nil,
    directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
  )
}
