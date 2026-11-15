import Foundation

/// A `KeyValueStoring` that reads through to `base` and writes only to an
/// in-memory overlay (I-6 Amendment 1, step A3).
///
/// Used when the process is **not persistent**: the store did not open, so the
/// app runs in memory. Preferences still read what the user last saved, so the
/// first-run flag and notification settings are right, but nothing this launch
/// writes reaches `UserDefaults`. The next launch, with the real store, reads
/// `base` as it was.
///
/// A key written here hides `base`'s value for that key, including a written
/// `nil`, so a read after `set(nil, …)` returns nil and not the stored value.
public final class ReadThroughKeyValueStore: KeyValueStoring, @unchecked Sendable {
  private let base: any KeyValueStoring
  private let overlay = InMemoryKeyValueStore()
  private let lock = NSLock()
  private var written: Set<String> = []

  public init(reading base: any KeyValueStoring) {
    self.base = base
  }

  public func bool(forKey key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return written.contains(key) ? overlay.bool(forKey: key) : base.bool(forKey: key)
  }

  public func set(_ value: Bool, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    overlay.set(value, forKey: key)
    written.insert(key)
  }

  public func data(forKey key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return written.contains(key) ? overlay.data(forKey: key) : base.data(forKey: key)
  }

  public func set(_ value: Data?, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    overlay.set(value, forKey: key)
    written.insert(key)
  }
}
