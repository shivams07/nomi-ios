import XCTest

/// Holds a continuation it never resumes, so the work it backs ignores cancellation.
/// Stored, so the continuation is not reported as leaked.
private actor NeverResumed {
  private var parked: CheckedContinuation<Int, Never>?

  func park() async -> Int {
    await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
      parked = continuation
    }
  }
}

final class TestTimeoutTests: XCTestCase {

  /// The R5d hang in miniature: a task group would wait for the child that ignores
  /// cancellation, so this test only returns when the timeout does not wait for it.
  func testATimeoutReturnsEvenWhenTheWorkIgnoresCancellation() async {
    let parker = NeverResumed()
    let start = ContinuousClock.now

    do {
      _ = try await withTestTimeout(seconds: 0.2) { await parker.park() }
      XCTFail("a parked work item was supposed to time out")
    } catch {
      XCTAssertEqual(error as? TestTimeout, TestTimeout(seconds: 0.2), "got \(error)")
    }

    XCTAssertLessThan(start.duration(to: .now), .seconds(2))
  }

  func testATimeoutFailsAStreamThatNeverYields() async {
    let (stream, continuation) = AsyncStream<Int>.makeStream()
    defer { continuation.finish() }

    do {
      _ = try await collect(stream, count: 1, seconds: 0.2)
      XCTFail("a stream that never yields was supposed to time out")
    } catch {
      XCTAssertEqual(error as? TestTimeout, TestTimeout(seconds: 0.2), "got \(error)")
    }
  }

  func testFinishedWorkReturnsItsValue() async throws {
    let value = try await withTestTimeout { 42 }
    XCTAssertEqual(value, 42)
  }

  func testCollectReturnsTheFirstNElements() async throws {
    let (stream, continuation) = AsyncStream<Int>.makeStream()
    for value in 1...4 { continuation.yield(value) }
    continuation.finish()

    let collected = try await collect(stream, count: 3)
    XCTAssertEqual(collected, [1, 2, 3])
  }

  func testCollectReturnsFewerWhenTheStreamFinishes() async throws {
    let (stream, continuation) = AsyncStream<Int>.makeStream()
    continuation.yield(1)
    continuation.finish()

    let collected = try await collect(stream, count: 3)
    XCTAssertEqual(collected, [1])
  }
}
