import Foundation
import NomiCore
import Observation

/// What the check screen shows. `.ready` carries the dry run's counts and the
/// mapping they were counted under, so the tiles and Import describe the same
/// rows.
enum ImportCheckState {
  case loading
  case needsColumns(ImportPreview)
  case ready(ImportPreview, ImportDryRun, ColumnMapping)
  case failed(String)
  case importing
  case done(ImportSummary)
}

/// The Import check screen's state and work (S11, I-12). Inspects the file,
/// counts it with `dryRun`, and commits. The column mapping is saved only after
/// a commit succeeds.
@Observable @MainActor
final class ImportCheckModel {
  let url: URL
  @ObservationIgnored private let service: any FileImportService

  private(set) var state: ImportCheckState
  /// The inspected preview, kept across states so the mapping sheet still has its headers.
  private(set) var inspected: ImportPreview?
  /// The mapping the sheet edits and the next dry run or commit uses.
  private(set) var mapping: ColumnMapping?
  /// True while a dry run for a new mapping is in flight. Import is disabled then.
  private(set) var isCounting = false
  /// Set when a commit fails after a count was shown. Cleared by the next attempt.
  private(set) var commitNote: String?

  /// Bumped by every load and count. A result is written only if its token is still current.
  @ObservationIgnored private var generation = 0
  /// What "Try again" repeats.
  @ObservationIgnored private var lastAttempt: Attempt = .load

  private enum Attempt {
    case load
    case mapping(ColumnMapping)
  }

  /// `seed` lets a preview start on any state. A seeded state also seeds the preview and mapping it carries.
  init(service: any FileImportService, url: URL, seed: ImportCheckState = .loading) {
    self.service = service
    self.url = url
    self.state = seed
    switch seed {
    case .ready(let preview, _, let mapping):
      inspected = preview
      self.mapping = mapping
    case .needsColumns(let preview):
      inspected = preview
      mapping = ImportLogic.fallbackMapping(for: preview)
    case .loading, .failed, .importing, .done:
      break
    }
  }

  /// Inspects the file. A format with a mapping goes straight to the count. One
  /// without a mapping, or a mapping that parses no new or already-known rows,
  /// goes to the column mapping first.
  func load() async {
    lastAttempt = .load
    let token = nextToken()
    state = .loading
    commitNote = nil
    do {
      let preview = try await accessing { try await service.inspect(url) }
      guard token == generation else { return }
      inspected = preview
      guard let suggested = preview.suggestedMapping else {
        mapping = ImportLogic.fallbackMapping(for: preview)
        state = .needsColumns(preview)
        return
      }
      mapping = suggested
      await count(preview, suggested, token: token, opensMappingOnZero: true)
    } catch {
      guard token == generation else { return }
      state = .failed(ImportLogic.inspectFailure(error))
    }
  }

  /// The column mapping sheet's Save (D13). Counts the file under the new mapping and
  /// writes nothing: the mapping is saved only after a commit succeeds.
  func applyMapping(_ mapping: ColumnMapping) async {
    switch state {
    case .needsColumns, .ready:
      await recount(mapping, opensMappingOnZero: false)
    case .loading, .failed, .importing, .done:
      return
    }
  }

  /// Commits the file under the mapping the counts were made with, then saves
  /// that mapping. A commit that throws keeps the counts on screen with a note.
  func importNow(accountID: UUID?) async {
    guard case .ready(let preview, let dry, let mapping) = state,
          ImportLogic.canImport(newCount: dry.newCount),
          !isCounting else { return }
    commitNote = nil
    state = .importing
    do {
      let summary = try await accessing { try await service.commit(url, mapping: mapping, accountID: accountID) }
      let key = SavedMappingKey.make(from: preview)
      do {
        try service.saveMapping(mapping, signature: key.signature, bankLabel: key.bankLabel)
      } catch {
        NomiLog.ingest.error("import mapping not saved: \(NomiLog.describe(error), privacy: .public)")
      }
      state = .done(summary)
    } catch {
      commitNote = ImportLogic.commitFailure
      state = .ready(preview, dry, mapping)
    }
  }

  /// "Try again" on the failed state: repeats whatever failed.
  func retry() async {
    switch lastAttempt {
    case .load:
      await load()
    case .mapping(let mapping):
      await recount(mapping, opensMappingOnZero: false)
    }
  }

  // MARK: - Counting

  /// Counts `mapping` and shows the result. Only the newest request may write its
  /// result: an earlier count that finishes late is dropped.
  private func recount(_ mapping: ColumnMapping, opensMappingOnZero: Bool) async {
    guard let preview = inspected else { return }
    lastAttempt = .mapping(mapping)
    let token = nextToken()
    self.mapping = mapping
    commitNote = nil
    await count(preview, mapping, token: token, opensMappingOnZero: opensMappingOnZero)
  }

  private func count(_ preview: ImportPreview, _ mapping: ColumnMapping, token: Int, opensMappingOnZero: Bool) async {
    isCounting = true
    do {
      let dry = try await accessing { try await service.dryRun(url, mapping: mapping) }
      guard token == generation else { return }
      isCounting = false
      if opensMappingOnZero && dry.newCount + dry.alreadyImportedCount == 0 {
        state = .needsColumns(preview)
      } else {
        state = .ready(preview, dry, mapping)
      }
    } catch {
      guard token == generation else { return }
      isCounting = false
      state = .failed(ImportLogic.countFailure)
    }
  }

  private func nextToken() -> Int {
    generation += 1
    return generation
  }

  /// Holds the file's security-scoped access for one call into the service, as the
  /// picker's callback does for each step.
  private func accessing<T>(_ work: () async throws -> T) async throws -> T {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }
    return try await work()
  }
}
