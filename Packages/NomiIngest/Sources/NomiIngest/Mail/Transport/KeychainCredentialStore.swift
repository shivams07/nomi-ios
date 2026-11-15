import Foundation
import NomiCore

#if canImport(Security)
  import Security
#endif

/// Where the mailbox password lives. Behind a protocol so nothing above it needs
/// the Security framework — including the tests, which cannot reach a keychain
/// at all (see `KeychainCredentialStore`).
public protocol MailCredentialStoring: Sendable {
  func save(_ credentials: IMAPCredentials) throws
  func load() throws -> IMAPCredentials?
  func delete() throws
}

public enum MailCredentialError: Error, Sendable, Equatable {
  case keychain(OSStatusCode)
  case malformedStoredItem
  case unavailableOnThisPlatform

  public typealias OSStatusCode = Int32
}

/// Keychain, `kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable`
/// false — both from §1.1, and both load-bearing.
///
/// **After-first-unlock is required, not preferred.** A background refresh on a
/// locked device cannot read a `WhenUnlocked` item, so mail capture would
/// silently stop working exactly when it is supposed to be working.
///
/// **Not synchronizable, and the consequence is user-visible.** A second device
/// shows every synced transaction and must have its mail password entered again:
/// transactions sync via CloudKit, the mailbox credential does not. That will
/// look like a sync bug when it happens, so it is written down here and belongs
/// in the Settings copy U7 owns.
///
/// Untestable from CI: a `swift test` binary has no keychain access group and
/// every call here returns `errSecMissingEntitlement`. Compile-verified only,
/// the same standing as every other system-framework boundary on this project.
public struct KeychainCredentialStore: MailCredentialStoring {
  private let service: String
  private let account: String
  #if canImport(Security)
    private let calls: KeychainItemCalls
  #endif

  public init(service: String = "ai.nomi.mail", account: String = "imap") {
    self.service = service
    self.account = account
    #if canImport(Security)
      self.calls = .security
    #endif
  }

  #if canImport(Security)
    /// Test seam: the same store over scripted SecItem calls. Nothing outside
    /// this file and its tests reaches it.
    init(service: String, account: String, calls: KeychainItemCalls) {
      self.service = service
      self.account = account
      self.calls = calls
    }
  #endif

  /// Writes in place. Never deletes first, so a failed write leaves the saved
  /// password as it was.
  public func save(_ credentials: IMAPCredentials) throws {
    #if canImport(Security)
      let payload = StoredCredentials(credentials)
      let data = try JSONEncoder().encode(payload)

      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]

      let updated = calls.update(baseQuery(), attributes)
      if updated == errSecSuccess { return }
      guard updated == errSecItemNotFound else { throw MailCredentialError.keychain(updated) }

      var query = baseQuery()
      query.merge(attributes) { _, new in new }
      let added = calls.add(query)
      if added == errSecSuccess { return }
      if added == errSecDuplicateItem {
        // Another writer added the item between our update and our add. Update it.
        let retried = calls.update(baseQuery(), attributes)
        guard retried == errSecSuccess else { throw MailCredentialError.keychain(retried) }
        return
      }
      throw MailCredentialError.keychain(added)
    #else
      throw MailCredentialError.unavailableOnThisPlatform
    #endif
  }

  public func load() throws -> IMAPCredentials? {
    #if canImport(Security)
      var query = baseQuery()
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else { throw MailCredentialError.keychain(status) }
      guard let data = item as? Data else { throw MailCredentialError.malformedStoredItem }
      let stored: StoredCredentials
      do {
        stored = try JSONDecoder().decode(StoredCredentials.self, from: data)
      } catch {
        NomiLog.sync.error("stored mail credential unreadable: \(NomiLog.describe(error), privacy: .public)")
        throw MailCredentialError.malformedStoredItem
      }
      return stored.credentials
    #else
      throw MailCredentialError.unavailableOnThisPlatform
    #endif
  }

  public func delete() throws {
    #if canImport(Security)
      let status = calls.delete(baseQuery())
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw MailCredentialError.keychain(status)
      }
    #else
      throw MailCredentialError.unavailableOnThisPlatform
    #endif
  }

  #if canImport(Security)
    private func baseQuery() -> [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        // Never true. See the type doc — this is the line that keeps the
        // password off iCloud Keychain.
        kSecAttrSynchronizable as String: false,
      ]
    }
  #endif

  /// `IMAPCredentials` is not `Codable` (it is U1's, and U1 had no reason to
  /// make it so). This is the wire form, and it stays private to the store.
  private struct StoredCredentials: Codable {
    let host: String
    let port: Int
    let address: String
    let password: String

    init(_ credentials: IMAPCredentials) {
      host = credentials.host
      port = credentials.port
      address = credentials.address
      password = credentials.password
    }

    var credentials: IMAPCredentials {
      IMAPCredentials(host: host, port: port, address: address, password: password)
    }
  }
}

#if canImport(Security)
  /// The three SecItem calls `KeychainCredentialStore` makes, as values, so a test
  /// can script them. `.security` is the real framework; nothing else builds one.
  struct KeychainItemCalls: Sendable {
    var update: @Sendable (_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    var add: @Sendable (_ attributes: [String: Any]) -> OSStatus
    var delete: @Sendable (_ query: [String: Any]) -> OSStatus

    static let security = KeychainItemCalls(
      update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
      add: { SecItemAdd($0 as CFDictionary, nil) },
      delete: { SecItemDelete($0 as CFDictionary) })
  }
#endif
