import NomiCore
import XCTest

@testable import NomiApp

/// `AsyncStream` is single-consumer, and four merged screens each open a
/// `for await` over `MailConnectionService.state`. These are the two properties
/// that make that safe.
///
/// Subscription happens synchronously inside `stream()` and the buffering policy
/// is `.unbounded`, so every case here can subscribe, publish, and *then*
/// iterate — no sleeps, no expectations, no timing.
final class StreamHubTests: XCTestCase {

  private func collect<T>(_ stream: AsyncStream<T>, count: Int) async -> [T] {
    var collected: [T] = []
    for await value in stream {
      collected.append(value)
      if collected.count == count { break }
    }
    return collected
  }

  /// The bug this type exists for: with a raw stream, each element goes to
  /// exactly one waiting consumer, so two screens would each see a different
  /// half of the transitions.
  func testEverySubscriberSeesEveryElement() async {
    let hub = StreamHub<Int>()
    let first = hub.stream()
    let second = hub.stream()

    hub.publish(1)
    hub.publish(2)
    hub.publish(3)

    let a = await collect(first, count: 3)
    let b = await collect(second, count: 3)

    XCTAssertEqual(a, [1, 2, 3])
    XCTAssertEqual(b, [1, 2, 3])
  }

  /// A stream only delivers what arrives after you subscribe, and these screens
  /// subscribe when they appear. Without the replay, Settings opened after a
  /// successful connect shows "not connected" until the next transition.
  func testALateSubscriberIsGivenTheCurrentValue() async {
    let hub = StreamHub<MailConnectionState>()
    hub.publish(.connecting)
    hub.publish(.connected(address: "a@b.com", lastSync: nil))

    let late = await collect(hub.stream(), count: 1)

    XCTAssertEqual(late, [.connected(address: "a@b.com", lastSync: nil)])
  }

  /// Only the *latest* is replayed, not the whole history — a screen appearing
  /// after six transitions wants the current state, not a replay of the session.
  func testOnlyTheLatestIsReplayed() async {
    let hub = StreamHub<Int>()
    hub.publish(1)
    hub.publish(2)

    let stream = hub.stream()
    hub.publish(3)

    // Hoisted: XCTAssertEqual takes autoclosures, and an autoclosure
    // cannot carry an `await`.
    let replayedAndNew = await collect(stream, count: 2)
    XCTAssertEqual(replayedAndNew, [2, 3])
  }

  func testASubscriberWithNoPublishedValueYetReceivesNothingUpFront() async {
    let hub = StreamHub<Int>()
    let stream = hub.stream()
    hub.publish(7)

    let received = await collect(stream, count: 1)
    XCTAssertEqual(received, [7])
  }

  func testFinishEndsExistingStreams() async {
    let hub = StreamHub<Int>()
    let stream = hub.stream()
    hub.publish(1)
    hub.finish()

    var collected: [Int] = []
    for await value in stream {
      collected.append(value)
    }

    // The loop terminates rather than hanging, which is the assertion — a
    // buffered element is still delivered before the finish.
    XCTAssertEqual(collected, [1])
  }

  /// Subscribing after `finish` must not hang forever waiting for a producer
  /// that has gone. It replays the last value and ends.
  func testSubscribingAfterFinishReplaysAndEnds() async {
    let hub = StreamHub<Int>()
    hub.publish(9)
    hub.finish()

    var collected: [Int] = []
    for await value in hub.stream() {
      collected.append(value)
    }

    XCTAssertEqual(collected, [9])
  }
}
