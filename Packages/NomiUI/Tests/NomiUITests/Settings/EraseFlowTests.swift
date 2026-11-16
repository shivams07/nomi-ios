import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// The Erase all Nomi data sheet (S9a step 5, I-13 Amendment 1): the typed gate, one
/// call to the eraser, the copy for each scope, and the copy for each failure.
@MainActor
final class EraseFlowTests: XCTestCase {
  private struct SpyFailure: Error {}

  /// Counts calls. Throws `error` when it is set.
  @MainActor
  private final class SpyEraser: DataErasing {
    var scope: EraseScope
    var error: Error?
    private(set) var calls = 0

    init(scope: EraseScope = .everywhere) {
      self.scope = scope
    }

    func eraseEverything() async throws {
      calls += 1
      if let error { throw error }
    }
  }

  /// Holds `eraseEverything` open until `release()`, so a test can look at the sheet mid-erase.
  @MainActor
  private final class BlockingEraser: DataErasing {
    var scope: EraseScope = .everywhere
    private(set) var calls = 0
    private var resume: CheckedContinuation<Void, Never>?

    var isBlocked: Bool { resume != nil }

    func eraseEverything() async throws {
      calls += 1
      await withCheckedContinuation { resume = $0 }
    }

    func release() {
      resume?.resume()
      resume = nil
    }
  }

  private let everywhereCopy =
    "Every transaction, account, budget and rule is removed from this iPhone and from your iCloud. Your other devices lose them too when they next sync. The mail password is removed from this iPhone; another device keeps its own until you erase or disconnect mail there. This cannot be undone."
  private let thisDeviceCopy =
    "Nomi isn’t syncing with iCloud right now, so this erases this iPhone only. If your data is in iCloud, it comes back the next time Nomi syncs. To erase it everywhere, turn iCloud on for Nomi and erase again. This cannot be undone on this iPhone."
  private let unavailableCopy =
    "Nomi couldn’t open your saved data this time, so there is nothing it can erase. Close Nomi and open it again, then try."
  private let busyCopy = "Nomi is still syncing. Nothing was erased. Try again in a moment."
  private let incompleteCopy = "Some data couldn’t be removed. Try again."

  // MARK: - The gate

  /// Only the exact word opens the gate. Case, spaces and a near miss all keep it shut.
  func testOnlyTheExactWordOpensTheGate() {
    let model = EraseDataModel(eraser: SpyEraser())

    model.confirmation = "ERASE"
    XCTAssertTrue(model.canErase)

    for typed in ["erase", "Erase", "ERASE ", " ERASE", "ERAS", "ERASEE", ""] {
      model.confirmation = typed
      XCTAssertFalse(model.canErase, "'\(typed)' must not open the gate")
    }
  }

  /// A closed gate never reaches the eraser, not even once.
  func testAClosedGateNeverCallsTheEraser() async {
    let spy = SpyEraser()
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "erase"

    let erased = await model.erase()

    XCTAssertFalse(erased)
    XCTAssertEqual(spy.calls, 0)
  }

  // MARK: - The call

  /// A confirmed erase calls the eraser exactly once and reports success.
  func testAConfirmedEraseCallsTheEraserOnceAndReportsSuccess() async {
    let spy = SpyEraser()
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "ERASE"

    let erased = await model.erase()

    XCTAssertTrue(erased)
    XCTAssertEqual(spy.calls, 1)
    XCTAssertNil(model.failureText)
    XCTAssertFalse(model.isErasing)
  }

  /// While the erase is running the sheet is busy: the gate is shut and a second press does nothing.
  func testWhileErasingTheGateShutsAndASecondPressDoesNothing() async throws {
    let eraser = BlockingEraser()
    let model = EraseDataModel(eraser: eraser)
    model.confirmation = "ERASE"

    let first = Task { await model.erase() }
    try await withTestTimeout {
      while !(await eraser.isBlocked) { await Task.yield() }
    }

    XCTAssertTrue(model.isErasing)
    XCTAssertFalse(model.canErase)
    let second = await model.erase()
    XCTAssertFalse(second)
    XCTAssertEqual(eraser.calls, 1)

    eraser.release()
    let firstResult = try await withTestTimeout { await first.value }
    XCTAssertTrue(firstResult)
  }

  // MARK: - Copy per scope

  func testEachScopeHasItsOwnBody() {
    XCTAssertEqual(EraseDataCopy.body(for: .everywhere), everywhereCopy)
    XCTAssertEqual(EraseDataCopy.body(for: .thisDeviceOnly), thisDeviceCopy)
    XCTAssertEqual(EraseDataCopy.body(for: .unavailable(reason: "retry later")), unavailableCopy)
  }

  /// The unavailable reason is developer text, so it goes to Copy details, not the body.
  func testOnlyTheUnavailableScopeHasDetailsToCopy() {
    XCTAssertEqual(SettingsLogic.copyableDetails(for: EraseScope.unavailable(reason: "retry later")), "retry later")
    XCTAssertNil(SettingsLogic.copyableDetails(for: EraseScope.everywhere))
    XCTAssertNil(SettingsLogic.copyableDetails(for: EraseScope.thisDeviceOnly))
    XCTAssertFalse(EraseDataCopy.body(for: .unavailable(reason: "retry later")).contains("retry later"))
  }

  // MARK: - Unavailable has no way to erase

  func testUnavailableHasNoEraseButtonAndNoWayToErase() async {
    let spy = SpyEraser(scope: .unavailable(reason: "retry later"))
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "ERASE"

    XCTAssertFalse(model.showsEraseButton)
    XCTAssertFalse(model.canErase)
    let erased = await model.erase()
    XCTAssertFalse(erased)
    XCTAssertEqual(spy.calls, 0)
  }

  // MARK: - Failures

  /// `busy` says nothing was erased and the gate reopens, so the user can try again.
  func testBusyShowsItsCopyAndReopensTheGate() async {
    let spy = SpyEraser()
    spy.error = EraseError.busy
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "ERASE"

    let erased = await model.erase()

    XCTAssertFalse(erased)
    XCTAssertEqual(model.failureText, busyCopy)
    XCTAssertFalse(model.isErasing)
    XCTAssertTrue(model.canErase)
  }

  func testIncompleteShowsItsCopyAndReopensTheGate() async {
    let spy = SpyEraser()
    spy.error = EraseError.incomplete
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "ERASE"

    let erased = await model.erase()

    XCTAssertFalse(erased)
    XCTAssertEqual(model.failureText, incompleteCopy)
    XCTAssertTrue(model.canErase)
  }

  /// Anything the eraser throws that is not one of its three cases may still have
  /// removed some data, so it reads as incomplete, which is safe to retry.
  func testAnUnexpectedErrorReadsAsIncomplete() {
    XCTAssertEqual(EraseDataCopy.failureText(for: SpyFailure()), incompleteCopy)
  }

  /// `.unavailable` cannot reach the button, but if it were thrown it still says what is true.
  func testAnUnavailableErrorSaysThereIsNothingToErase() {
    XCTAssertEqual(EraseDataCopy.failureText(for: EraseError.unavailable(reason: "x")), unavailableCopy)
  }

  /// A retry that succeeds clears the failure from the sheet.
  func testARetryThatSucceedsClearsTheFailure() async {
    let spy = SpyEraser()
    spy.error = EraseError.busy
    let model = EraseDataModel(eraser: spy)
    model.confirmation = "ERASE"
    _ = await model.erase()
    XCTAssertEqual(model.failureText, busyCopy)

    spy.error = nil
    let erased = await model.erase()

    XCTAssertTrue(erased)
    XCTAssertNil(model.failureText)
    XCTAssertEqual(spy.calls, 2)
  }
}
