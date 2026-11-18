import Foundation
import XCTest

@testable import NomiApp

/// The counting and refusal rules of `MailWorkGate`, on their own. The erase
/// behaviour that depends on them is in `EraseDrainsMailWorkTests`.
final class MailWorkGateTests: XCTestCase {

  /// `enter` counts a call in and `exit` counts it out, so `isBusy` tracks what
  /// is actually inside a sync or backfill.
  func testEnterAndExitTrackWhatIsRunning() throws {
    let gate = MailWorkGate()
    XCTAssertFalse(gate.isBusy)

    try gate.enter()
    XCTAssertTrue(gate.isBusy)
    try gate.enter()
    gate.exit()
    XCTAssertTrue(gate.isBusy, "one call is still inside")
    gate.exit()
    XCTAssertFalse(gate.isBusy)
  }

  /// A closed gate refuses a new call with `CancellationError` and counts nothing,
  /// so a refused call cannot keep an erase waiting.
  func testAClosedGateRefusesWithoutCounting() throws {
    let gate = MailWorkGate()
    gate.close()

    XCTAssertThrowsError(try gate.enter()) { error in
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertFalse(gate.isBusy, "a refused call is not running")
    XCTAssertTrue(gate.isClosed)
  }

  /// Closing the gate does not stop a call that is already inside. The erase
  /// waits for it, so `isBusy` stays true until that call exits.
  func testClosingDoesNotEndACallAlreadyRunning() throws {
    let gate = MailWorkGate()
    try gate.enter()

    gate.close()
    XCTAssertTrue(gate.isBusy, "the call inside is still counted")

    gate.exit()
    XCTAssertFalse(gate.isBusy)
  }

  /// Reopening admits calls again, which is what ends an erase.
  func testReopenAdmitsCallsAgain() throws {
    let gate = MailWorkGate()
    gate.close()
    XCTAssertThrowsError(try gate.enter())

    gate.reopen()
    XCTAssertFalse(gate.isClosed)
    try gate.enter()
    XCTAssertTrue(gate.isBusy)
    gate.exit()
  }
}
