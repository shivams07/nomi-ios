import Foundation

/// Tracks `dedupeKey`s already committed through this `FileImportService`
/// instance, so a re-import — even with rows reordered — merges instead of
/// duplicating. `FileImportService` never writes `Transaction` rows itself
/// (design note: "produces `TransactionDraft` only"); this store is the
/// in-unit stand-in for that check until the real write path (U4's
/// `IngestSink`) exists to consult instead.
public protocol ImportDedupeStore: Sendable {
  func containsAny(of keys: Set<String>) -> Set<String>
  func record(_ keys: Set<String>)
}

public final class InMemoryImportDedupeStore: ImportDedupeStore, @unchecked Sendable {
  private let lock = NSLock()
  private var seen: Set<String> = []

  public init() {}

  public func containsAny(of keys: Set<String>) -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return keys.intersection(seen)
  }

  public func record(_ keys: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    seen.formUnion(keys)
  }
}
