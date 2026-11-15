import NomiCore
import XCTest

@testable import NomiUI

/// The "Try again" offer on Connect mail. It shows only when a password is saved,
/// a connection was made before, and the connection is down (failed or
/// disconnected). The table covers every state, not only the two that show it.
final class ConnectMailReconnectTests: XCTestCase {

  private let connected = MailConnectionState.connected(address: "shivam@example.com", lastSync: nil)

  func testOfferTruthTable() {
    // state, hadConnection, hasStoredCredential, expected
    let rows: [(MailConnectionState, Bool, Bool, Bool)] = [
      (.disconnected, false, false, false),
      (.disconnected, false, true, false),
      (.disconnected, true, false, false),
      (.disconnected, true, true, true),
      (.connecting, false, false, false),
      (.connecting, false, true, false),
      (.connecting, true, false, false),
      (.connecting, true, true, false),
      (connected, false, false, false),
      (connected, false, true, false),
      (connected, true, false, false),
      (connected, true, true, false),
      (.failed(.connectionFailed), false, false, false),
      (.failed(.connectionFailed), false, true, false),
      (.failed(.connectionFailed), true, false, false),
      (.failed(.connectionFailed), true, true, true),
    ]
    for (index, row) in rows.enumerated() {
      let (state, hadConnection, hasStored, expected) = row
      XCTAssertEqual(
        ReconnectOffer.isShown(
          state: state, hadConnection: hadConnection, hasStoredCredential: hasStored),
        expected,
        "row \(index): state \(state), hadConnection \(hadConnection), hasStoredCredential \(hasStored)")
    }
  }

  /// Offline, rejected or unknown: the offer does not depend on which failure it was.
  func testEveryFailureOffersTheSameWay() {
    let failures: [MailError] = [.authenticationFailed, .connectionFailed, .unknown("")]
    for failure in failures {
      XCTAssertTrue(
        ReconnectOffer.isShown(
          state: .failed(failure), hadConnection: true, hasStoredCredential: true),
        "\(failure) with a saved password should offer Try again")
    }
  }
}
