import Foundation
import XCTest

@testable import NomiApp

/// The counting, refusal and cancellation rules of `MailWorkGate`, on their own.
/// The erase behaviour that depends on them is in `EraseDrainsMailWorkTests`.
final class MailWorkGateTests: XCTestCase {

  /// `enter` counts a sync in and `exit` counts it out, so `isBusy` tracks what
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
    gate.closeForErase()

    XCTAssertThrowsError(try gate.enter()) { error in
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertThrowsError(try gate.enterBackfill()) { error in
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertFalse(gate.isBusy, "a refused call is not running")
    XCTAssertTrue(gate.isClosed)
  }

  /// Closing the gate does not stop a sync already inside: the erase waits for it,
  /// so `isBusy` stays true until that sync exits. A sync is never cancelled.
  func testClosingDoesNotCancelOrEndASyncAlreadyRunning() throws {
    let gate = MailWorkGate()
    try gate.enter()

    gate.closeForErase()
    XCTAssertTrue(gate.isBusy, "the sync inside is still counted")

    gate.exit()
    XCTAssertFalse(gate.isBusy)
  }

  /// Closing the gate cancels every backfill that registered a cancel handle, and
  /// leaves the syncs alone.
  func testClosingForEraseCancelsARunningBackfill() throws {
    let gate = MailWorkGate()
    let backfill = try gate.enterBackfill()
    let cancelled = CancelRecord()
    gate.registerCancel(for: backfill) { cancelled.mark() }
    try gate.enter()

    XCTAssertFalse(cancelled.isMarked, "nothing is cancelled before the erase")
    gate.closeForErase()

    XCTAssertTrue(cancelled.isMarked, "the erase cancels the running backfill")
    XCTAssertTrue(gate.isBusy, "until the backfill exits, the erase still waits for it")
    gate.exitBackfill(backfill)
    XCTAssertTrue(gate.isBusy, "the sync is still inside, and is not cancelled")
    gate.exit()
    XCTAssertFalse(gate.isBusy)
  }

  /// A backfill counted just before the erase closed the gate registers its cancel
  /// handle after the close. It is cancelled at once, so it cannot run past the erase.
  func testABackfillThatRegistersAfterTheCloseIsCancelledAtOnce() throws {
    let gate = MailWorkGate()
    let backfill = try gate.enterBackfill()
    gate.closeForErase()

    let cancelled = CancelRecord()
    gate.registerCancel(for: backfill) { cancelled.mark() }

    XCTAssertTrue(cancelled.isMarked, "a late registration is cancelled immediately")
    gate.exitBackfill(backfill)
    XCTAssertFalse(gate.isBusy)
  }

  /// A backfill that has exited is no longer a target. A later erase has nothing to cancel.
  func testAFinishedBackfillIsNotCancelledByALaterErase() throws {
    let gate = MailWorkGate()
    let backfill = try gate.enterBackfill()
    let cancelled = CancelRecord()
    gate.registerCancel(for: backfill) { cancelled.mark() }
    gate.exitBackfill(backfill)

    gate.closeForErase()
    XCTAssertFalse(cancelled.isMarked)
  }

  /// Reopening admits calls again, which is what ends an erase.
  func testReopenAdmitsCallsAgain() throws {
    let gate = MailWorkGate()
    gate.closeForErase()
    XCTAssertThrowsError(try gate.enter())

    gate.reopen()
    XCTAssertFalse(gate.isClosed)
    try gate.enter()
    XCTAssertTrue(gate.isBusy)
    gate.exit()
  }
}

/// Records that a cancel handle ran. A lock, because the handle is a Sendable closure.
private final class CancelRecord: @unchecked Sendable {
  private let lock = NSLock()
  private var marked = false

  func mark() {
    lock.lock()
    marked = true
    lock.unlock()
  }

  var isMarked: Bool {
    lock.lock()
    defer { lock.unlock() }
    return marked
  }
}
