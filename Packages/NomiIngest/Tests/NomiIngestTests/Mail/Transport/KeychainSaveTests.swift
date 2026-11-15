#if canImport(Security)
  import Foundation
  import NomiCore
  import Security
  import XCTest

  @testable import NomiIngest

  /// `KeychainCredentialStore.save` over scripted SecItem calls. A test binary has
  /// no keychain access group, so the real calls cannot be exercised here; the
  /// order of calls and the arguments are what these tests pin.
  final class KeychainSaveTests: XCTestCase {
    private let credentials = IMAPCredentials(
      host: "imap.example.com", port: 993, address: "someone@example.com", password: "app-password")

    // MARK: - save never deletes first

    /// The item exists, so the update lands in place. Nothing is deleted first,
    /// so a failure later in the sequence cannot take the saved password with it.
    func testSavingOverAnExistingItemUpdatesItInPlace() throws {
      let recorder = KeychainCallRecorder(script: ["update": [errSecSuccess]])
      let store = makeStore(recorder)

      try store.save(credentials)

      XCTAssertEqual(recorder.calls, ["update"])
    }

    func testSavingWithNothingStoredAdds() throws {
      let recorder = KeychainCallRecorder(
        script: ["update": [errSecItemNotFound], "add": [errSecSuccess]])
      let store = makeStore(recorder)

      try store.save(credentials)

      XCTAssertEqual(recorder.calls, ["update", "add"])
    }

    func testAFailedUpdateThrowsAndTouchesNothingElse() {
      let recorder = KeychainCallRecorder(script: ["update": [errSecInteractionNotAllowed]])
      let store = makeStore(recorder)

      XCTAssertThrowsError(try store.save(credentials)) { error in
        XCTAssertEqual(error as? MailCredentialError, .keychain(errSecInteractionNotAllowed))
      }
      XCTAssertEqual(recorder.calls, ["update"])
    }

    /// The old password survives a failed add. The add is the only other write, and
    /// nothing is deleted before or after it.
    func testAFailedAddDeletesNothing() {
      let recorder = KeychainCallRecorder(
        script: ["update": [errSecItemNotFound], "add": [errSecMissingEntitlement]])
      let store = makeStore(recorder)

      XCTAssertThrowsError(try store.save(credentials)) { error in
        XCTAssertEqual(error as? MailCredentialError, .keychain(errSecMissingEntitlement))
      }
      XCTAssertEqual(recorder.calls, ["update", "add"])
    }

    /// Another writer added the item between our update and our add. Update once more.
    func testADuplicateOnAddRetriesTheUpdateOnce() throws {
      let recorder = KeychainCallRecorder(
        script: [
          "update": [errSecItemNotFound, errSecSuccess],
          "add": [errSecDuplicateItem],
        ])
      let store = makeStore(recorder)

      try store.save(credentials)

      XCTAssertEqual(recorder.calls, ["update", "add", "update"])
    }

    func testADuplicateWhoseRetryFailsThrowsTheRetryStatus() {
      let recorder = KeychainCallRecorder(
        script: [
          "update": [errSecItemNotFound, errSecInteractionNotAllowed],
          "add": [errSecDuplicateItem],
        ])
      let store = makeStore(recorder)

      XCTAssertThrowsError(try store.save(credentials)) { error in
        XCTAssertEqual(error as? MailCredentialError, .keychain(errSecInteractionNotAllowed))
      }
      XCTAssertEqual(recorder.calls, ["update", "add", "update"])
    }

    // MARK: - what the update writes

    func testUpdateWritesThePayloadAndAccessibility() throws {
      let recorder = KeychainCallRecorder(script: ["update": [errSecSuccess]])
      let store = makeStore(recorder)

      try store.save(credentials)

      let update = try XCTUnwrap(recorder.lastUpdate)

      let data = try XCTUnwrap(update.attributes[kSecValueData as String] as? Data)
      let payload = try JSONDecoder().decode(DecodedPayload.self, from: data)
      XCTAssertEqual(payload.host, "imap.example.com")
      XCTAssertEqual(payload.port, 993)
      XCTAssertEqual(payload.address, "someone@example.com")
      XCTAssertEqual(payload.password, "app-password")

      XCTAssertEqual(
        update.attributes[kSecAttrAccessible as String] as? String,
        kSecAttrAccessibleAfterFirstUnlock as String)

      // The query finds the item; it never carries the payload, and it stays off iCloud.
      XCTAssertEqual(
        update.query[kSecAttrSynchronizable as String] as? Bool, false)
      XCTAssertNil(update.query[kSecValueData as String])
      XCTAssertNotNil(update.query[kSecClass as String])

      // The attributes must not re-declare the item's class or sync flag.
      XCTAssertNil(update.attributes[kSecClass as String])
      XCTAssertNil(update.attributes[kSecAttrSynchronizable as String])
    }

    // MARK: - delete is unchanged in behaviour

    func testDeleteStillDeletesAndToleratesNotFound() throws {
      let recorder = KeychainCallRecorder(script: ["delete": [errSecItemNotFound]])
      let store = makeStore(recorder)

      try store.delete()

      XCTAssertEqual(recorder.calls, ["delete"])
    }

    // MARK: - helpers

    private func makeStore(_ recorder: KeychainCallRecorder) -> KeychainCredentialStore {
      KeychainCredentialStore(
        service: "ai.nomi.mail.tests", account: "imap-tests", calls: recorder.item)
    }

    private struct DecodedPayload: Decodable {
      let host: String
      let port: Int
      let address: String
      let password: String
    }
  }

  /// Answers each named SecItem call from its own queue of statuses (success once a
  /// queue is empty), and records the call names in order. The last update's query
  /// and attributes are kept for inspection.
  private final class KeychainCallRecorder: @unchecked Sendable {
    struct Update {
      let query: [String: Any]
      let attributes: [String: Any]
    }

    private let lock = NSLock()
    private var script: [String: [OSStatus]]
    private(set) var calls: [String] = []
    private(set) var lastUpdate: Update?

    init(script: [String: [OSStatus]]) {
      self.script = script
    }

    var item: KeychainItemCalls {
      KeychainItemCalls(
        update: { query, attributes in
          self.record("update", query: query, attributes: attributes)
        },
        add: { attributes in
          self.record("add", query: attributes, attributes: [:])
        },
        delete: { query in
          self.record("delete", query: query, attributes: [:])
        })
    }

    private func record(
      _ name: String, query: [String: Any], attributes: [String: Any]
    ) -> OSStatus {
      lock.lock()
      defer { lock.unlock() }
      calls.append(name)
      if name == "update" {
        lastUpdate = Update(query: query, attributes: attributes)
      }
      guard var queue = script[name], !queue.isEmpty else { return errSecSuccess }
      let status = queue.removeFirst()
      script[name] = queue
      return status
    }
  }
#endif
