import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `ConnectMailModel` with a spy service (T2a). Each returned Task is awaited under
/// `withTestTimeout`, and nothing sleeps. The kill list is in each test's comment.
@MainActor
final class ConnectMailModelTests: XCTestCase {
  private let saved = Date(timeIntervalSince1970: 1_794_000_000)

  private func awaitTask(_ task: Task<Void, Never>) async throws {
    try await withTestTimeout { await task.value }
  }

  /// Tapping Try again reconnects with the saved password. It never calls
  /// `connect`, which would send the form's values. Kills T2-M1.
  func testTryAgainUsesTheSavedPasswordNotTheForm() async throws {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)
    _ = model.observe(.failed(.connectionFailed))

    try await awaitTask(model.tryAgain())

    XCTAssertEqual(spy.calls, [.reconnect])
  }

  /// A rejected password the service deleted hides the offer. The spy yields no
  /// state, so only the defer re-read can hide it. Kills T2-M2, T2-M7.
  func testTryAgainHidesTheOfferWhenTheRejectedPasswordWasDeleted() async throws {
    let spy = MailConnectionSpy()
    spy.reconnectDeletesCredential = true
    spy.fail(.reconnect, with: MailError.authenticationFailed)
    let model = ConnectMailModel(service: spy)
    _ = model.observe(.failed(.connectionFailed))
    XCTAssertTrue(model.isReconnectOfferShown)

    try await awaitTask(model.tryAgain())

    XCTAssertFalse(model.isReconnectOfferShown)
    XCTAssertFalse(model.hasSaved)
    XCTAssertFalse(model.isConnecting)
    XCTAssertTrue(model.didAttemptOnce)
  }

  func testTryAgainMarksConnectingUntilItEnds() async throws {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)

    let task = model.tryAgain()
    XCTAssertTrue(model.isConnecting)

    try await awaitTask(task)
    XCTAssertFalse(model.isConnecting)
  }

  /// A state change re-reads the saved-credential flag, so the offer follows the
  /// keychain. Kills T2-M3, T2-M7.
  func testStateChangeRereadsTheSavedPassword() {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)
    _ = model.observe(.failed(.connectionFailed))
    XCTAssertTrue(model.isReconnectOfferShown)

    spy.setStoredCredential(false)
    _ = model.observe(.disconnected)

    XCTAssertFalse(model.isReconnectOfferShown)
  }

  func testObserveConnectedReportsItAndRemembersTheConnection() {
    let spy = MailConnectionSpy(history: MailConnectionHistory(hasEverConnected: false, lastSync: nil))
    let model = ConnectMailModel(service: spy)
    XCTAssertFalse(model.hadConnection)

    let seen = model.observe(.connected(address: "a@b.in", lastSync: saved))

    XCTAssertTrue(seen.becameConnected)
    XCTAssertTrue(model.hadConnection)
    XCTAssertEqual(model.lastKnownSync, saved)
  }

  /// A failure is announced only after an attempt, so the screen does not read out a
  /// failure it has not caused.
  func testFailureAfterAnAttemptIsAnnounced() async throws {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)
    XCTAssertNil(model.observe(.failed(.authenticationFailed)).announcement)

    try await awaitTask(model.tryAgain())

    XCTAssertEqual(
      model.observe(.failed(.authenticationFailed)).announcement,
      MailErrorMessage.text(for: .authenticationFailed))
  }

  func testDisconnectAsksFirst() {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)

    model.requestDisconnect()

    XCTAssertTrue(model.isConfirmingDisconnect)
    XCTAssertEqual(spy.calls, [])
  }

  /// Without a request, confirming does nothing. Kills T2-M5.
  func testConfirmWithoutAskingDoesNothing() {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)

    XCTAssertNil(model.confirmDisconnect())
    XCTAssertEqual(spy.calls, [])
  }

  /// One request, one disconnect: the second confirm finds the guard disarmed.
  /// Kills T2-M4: the mutant disarms inside request, so the unwrap fails.
  func testConfirmAfterAskingDisconnectsOnce() async throws {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)
    model.requestDisconnect()

    let task = try XCTUnwrap(model.confirmDisconnect())
    try await awaitTask(task)

    XCTAssertEqual(spy.calls, [.disconnect])
    XCTAssertNil(model.confirmDisconnect())
    XCTAssertEqual(spy.calls, [.disconnect])
  }

  /// Cancelling disarms, so a later confirm does nothing. Kills T2-M6.
  func testCancelDisarms() {
    let spy = MailConnectionSpy()
    let model = ConnectMailModel(service: spy)
    model.requestDisconnect()

    model.cancelDisconnect()

    XCTAssertNil(model.confirmDisconnect())
    XCTAssertEqual(spy.calls, [])
  }

  func testDisconnectFailureShowsTheAlertCopy() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.disconnect, with: MailError.connectionFailed)
    let model = ConnectMailModel(service: spy)
    model.requestDisconnect()

    let task = try XCTUnwrap(model.confirmDisconnect())
    try await awaitTask(task)

    XCTAssertEqual(model.errorMessage, "Couldn't disconnect right now. Try again in a moment.")
  }

  func testSyncNowFailureShowsTheAlertCopy() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.syncNow, with: MailError.connectionFailed)
    let model = ConnectMailModel(service: spy)

    try await awaitTask(model.syncNow())

    XCTAssertEqual(model.errorMessage, "Couldn't sync right now. Try again in a moment.")
  }
}
