import Foundation

/// Written when the app moves an unopenable store aside and starts a fresh one.
///
/// `fileName` is the moved main file's name inside `Recovered/`, for example
/// `default-20261114T093012.store`. It names the file, not its full path, so a
/// notice stays correct if the app container moves.
public struct StoreRecoveryNotice: Codable, Sendable, Equatable {
  public let movedAt: Date
  public let fileName: String

  public init(movedAt: Date, fileName: String) {
    self.movedAt = movedAt
    self.fileName = fileName
  }
}

/// Persists the latest `StoreRecoveryNotice` in `UserDefaults`, as JSON under
/// `defaultsKey`. Keeping it in defaults rather than in the store means it
/// survives the store being replaced, which is the point of recording it.
public enum StoreRecoveryRecord {
  public static let defaultsKey = "nomi.storeRecovery"

  /// Returns `nil` when nothing was recorded or the stored value does not
  /// decode.
  public static func load(from defaults: UserDefaults) -> StoreRecoveryNotice? {
    guard let data = defaults.data(forKey: defaultsKey) else { return nil }
    return try? JSONDecoder().decode(StoreRecoveryNotice.self, from: data)
  }

  public static func save(_ notice: StoreRecoveryNotice, to defaults: UserDefaults) {
    // A two-field struct of a `Date` and a `String` always encodes, so the
    // `try?` cannot drop a real value.
    guard let data = try? JSONEncoder().encode(notice) else { return }
    defaults.set(data, forKey: defaultsKey)
  }

  public static func clear(in defaults: UserDefaults) {
    defaults.removeObject(forKey: defaultsKey)
  }
}
