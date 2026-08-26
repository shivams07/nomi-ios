import Foundation
import NomiCore

/// Learned CSV/XLSX layout, keyed by `FormatSignature`. Decoupled from
/// `ColumnMappingRecord` (a SwiftData `@Model`) so it can be exercised under
/// `swift test`, which cannot construct `@Model` instances headlessly — see
/// `InMemoryModelContainer`'s note. A `@Model`-backed conformance is the
/// app-wiring layer's job, outside this unit.
public protocol ColumnMappingStore: Sendable {
  func mapping(forSignature signature: String) -> SavedColumnMapping?
  func save(_ mapping: ColumnMapping, signature: String, bankLabel: String)
}

public struct SavedColumnMapping: Sendable, Equatable {
  public let mapping: ColumnMapping
  public let bankLabel: String

  public init(mapping: ColumnMapping, bankLabel: String) {
    self.mapping = mapping
    self.bankLabel = bankLabel
  }
}

/// Default in-process store. A fresh instance only remembers mappings saved
/// during its own lifetime — real cross-launch persistence is
/// `ColumnMappingRecord` via SwiftData, wired by the app layer.
public final class InMemoryColumnMappingStore: ColumnMappingStore, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: SavedColumnMapping] = [:]

  public init() {}

  public func mapping(forSignature signature: String) -> SavedColumnMapping? {
    lock.lock()
    defer { lock.unlock() }
    return storage[signature]
  }

  public func save(_ mapping: ColumnMapping, signature: String, bankLabel: String) {
    lock.lock()
    defer { lock.unlock() }
    storage[signature] = SavedColumnMapping(mapping: mapping, bankLabel: bankLabel)
  }
}
