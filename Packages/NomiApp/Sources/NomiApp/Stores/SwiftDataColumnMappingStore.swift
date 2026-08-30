import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// `ColumnMappingStore` over `ColumnMappingRecord`.
///
/// The `@Model` has been in the schema since U1 and never had a store, so
/// `FileImportServiceImpl` took its `InMemoryColumnMappingStore` default and
/// every learned mapping died with the process. A user who told the app which
/// column held the date was asked again on the next launch, and
/// `ImportPreview.detectedBankLabel` could only ever come from `BankPresets` —
/// the presets exist precisely so that a bank *without* one costs "one manual
/// mapping, once", which was never true because the mapping was never kept.
///
/// **A fresh `ModelContext` per call, rather than one held for the store's
/// lifetime.** Two reasons, and the first is a rule rather than a preference:
/// `ColumnMappingStore` is `Sendable` and not `@MainActor` — `FileImportServiceImpl`
/// calls it from a nonisolated async context — while `ModelContext` is neither,
/// so a held context would be exactly the non-`Sendable` state a `Sendable` type
/// may not have. `ModelContainer` *is* `Sendable`, and making a context from one
/// is the supported way to reach the store off the main actor. This is also why
/// it does not take `container.mainContext` the way `SwiftDataRuleStore` and its
/// siblings do: those satisfy `@MainActor` protocols in `NomiCore`, and this one
/// does not.
///
/// The second reason is that a context caches what it has read. A held one would
/// not see a mapping written through a different context — which is the
/// cross-instance visibility this type exists to give.
///
/// **Compile-verified only, in part.** `swift test` in this CI cannot construct
/// a `ModelContainer` (`NomiCore/Support/InMemoryModelContainer.swift` explains
/// why), so keep decisions out of here: the encode/decode and the upsert choice
/// are split into `ColumnMappingCoding` below, which is pure and is what
/// `ColumnMappingStoreTests` exercises.
public final class SwiftDataColumnMappingStore: ColumnMappingStore, @unchecked Sendable {
  /// `@unchecked` because the compiler cannot see that a `ModelContainer` is
  /// safe to use from several threads. It is — it is `Sendable` itself, and
  /// every `ModelContext` made from it here is created, used and dropped inside
  /// one synchronous call.
  private let container: ModelContainer

  public init(container: ModelContainer) {
    self.container = container
  }

  public func mapping(forSignature signature: String) -> SavedColumnMapping? {
    let context = ModelContext(container)
    guard let record = Self.record(forSignature: signature, in: context) else { return nil }
    return ColumnMappingCoding.saved(fromJSON: record.mappingJSON, bankLabel: record.bankLabel)
  }

  /// An upsert, not an insert.
  ///
  /// `FileImportServiceImpl` calls this on every commit, so a user re-importing
  /// the same bank's statement each month would otherwise accumulate a row per
  /// import and the read below would start picking between them.
  public func save(_ mapping: ColumnMapping, signature: String, bankLabel: String) {
    guard let json = ColumnMappingCoding.json(from: mapping) else { return }

    let context = ModelContext(container)
    if let existing = Self.record(forSignature: signature, in: context) {
      existing.bankLabel = bankLabel
      existing.mappingJSON = json
    } else {
      context.insert(
        ColumnMappingRecord(
          formatSignature: signature,
          bankLabel: bankLabel,
          mappingJSON: json
        )
      )
    }

    // Swallowed because `ColumnMappingStore` does not throw and there is nowhere
    // to report to: this is called from `saveMapping`, whose whole job is a
    // convenience for next time. A failure here costs the user one re-mapping,
    // not an import.
    try? context.save()
  }

  /// **Which record wins is unspecified when there is more than one.** CloudKit
  /// forbids unique constraints (see `NomiModelContainer`), so two devices can
  /// each learn the same format and sync merges them into two rows — the same
  /// R5 shape `IngestPipeline.reconcile()` exists for on transactions.
  ///
  /// Left alone rather than resolved. Picking the newest needs a timestamp on
  /// `ColumnMappingRecord`, which is a schema change on live data and not this
  /// unit; and collapsing duplicates here would mean this store deleting rows on
  /// a synced database as a side effect of a read. What the user sees in the
  /// worse case is one of two mappings they wrote themselves, offered as a
  /// *suggestion* on the import screen that they can change before committing.
  private static func record(
    forSignature signature: String,
    in context: ModelContext
  ) -> ColumnMappingRecord? {
    var descriptor = FetchDescriptor<ColumnMappingRecord>(
      predicate: #Predicate<ColumnMappingRecord> { $0.formatSignature == signature }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }
}

/// The part of the store that decides anything, with no `@Model` and no
/// container in it.
///
/// It is separate because nothing above it can be executed on this project:
/// `swift test` cannot construct a `ModelContainer` in this CI, so a
/// `mappingJSON` written in a shape `mapping(forSignature:)` cannot read back
/// would be a silent, permanent "the app never remembers my bank" with no test
/// anywhere able to catch it. Here, it is one round-trip assertion.
enum ColumnMappingCoding {
  static func json(from mapping: ColumnMapping) -> String? {
    guard let data = try? JSONEncoder().encode(mapping) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// A `nil` here means the stored JSON is unreadable — an older shape of
  /// `ColumnMapping`, or a truncated write. Treated as "no mapping learned"
  /// rather than as an error: the import screen then falls back to
  /// `BankPresets` or asks, which is what it does for a format never seen
  /// before and is the right behaviour for one whose record is unusable.
  static func saved(fromJSON json: String, bankLabel: String) -> SavedColumnMapping? {
    guard let mapping = try? JSONDecoder().decode(ColumnMapping.self, from: Data(json.utf8))
    else { return nil }
    return SavedColumnMapping(mapping: mapping, bankLabel: bankLabel)
  }
}
