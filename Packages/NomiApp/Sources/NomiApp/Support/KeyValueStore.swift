import Foundation

/// The app's small-state seam: the first-run flag, `NotificationSettings`, and
/// the mail sync cursor.
///
/// A protocol rather than `UserDefaults` directly, and not for purity — under
/// `swift test` `UserDefaults.standard` is the *test runner's* domain, shared
/// across every test in the process and persisted between runs. A test that
/// wrote a first-run flag there would pass alone and fail in a suite, or pass
/// on a clean machine and fail on the second run. `InMemoryKeyValueStore` is
/// what the tests use; `UserDefaultsKeyValueStore` is what the app uses.
///
/// Deliberately not `@AppStorage`. `@AppStorage` is a view-layer property
/// wrapper that reads `UserDefaults.standard` and cannot be injected, so the
/// first-run decision would only ever be testable by mutating global state.
public protocol KeyValueStoring: AnyObject, Sendable {
  func bool(forKey key: String) -> Bool
  func set(_ value: Bool, forKey key: String)
  func data(forKey key: String) -> Data?
  func set(_ value: Data?, forKey key: String)
}

public final class UserDefaultsKeyValueStore: KeyValueStoring, @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
  public func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
  public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

  public func set(_ value: Data?, forKey key: String) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}

public final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var bools: [String: Bool] = [:]
  private var blobs: [String: Data] = [:]

  public init() {}

  public func bool(forKey key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return bools[key] ?? false
  }

  public func set(_ value: Bool, forKey key: String) {
    lock.lock()
    bools[key] = value
    lock.unlock()
  }

  public func data(forKey key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return blobs[key]
  }

  public func set(_ value: Data?, forKey key: String) {
    lock.lock()
    blobs[key] = value
    lock.unlock()
  }
}

/// Every key this app writes to the key-value store, in one place, so a
/// collision is visible rather than discovered.
public enum PreferenceKey {
  public static let hasCompletedFirstRun = "nomi.hasCompletedFirstRun"
  public static let notificationSettings = "nomi.notificationSettings"
  public static let mailSyncCursor = "nomi.mailSyncCursor"
}
