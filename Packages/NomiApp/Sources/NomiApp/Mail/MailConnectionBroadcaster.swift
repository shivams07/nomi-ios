import Foundation
import NomiCore

/// Fans one `AsyncStream` out to every screen that wants it, and replays the
/// most recent element to whoever subscribes next.
///
/// **This exists because `AsyncStream` is single-consumer, and U8 is where that
/// stops being an abstract fact.** `IMAPMailConnectionService` says so in its
/// own comment — "U8 consumes each of these exactly once, at the composition
/// root; a second `for await` over the same stream would compete for elements
/// rather than mirror them" — and four merged screens each open their own
/// `for await` over `mailConnectionService.state`: `DashboardView`,
/// `SettingsScreen`, `ConnectMailScreen` and `BackfillScreen`. Handed the raw
/// service, each element would go to exactly one of them, chosen by whichever
/// task happened to be waiting. The visible symptom is a sync indicator that
/// updates on the dashboard *or* in Settings but never both, differently on
/// each launch.
///
/// **Replaying the latest element is the second half of the fix, not a bonus.**
/// A stream only ever delivers what arrives *after* you subscribe, and these
/// screens subscribe when they appear. Settings opened ten minutes after a
/// successful connect would sit on its initial `.disconnected` until the next
/// transition — showing "not connected" for a connected mailbox.
final class StreamHub<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var subscribers: [UUID: AsyncStream<Element>.Continuation] = [:]
  private var latest: Element?
  private var isFinished = false

  func stream() -> AsyncStream<Element> {
    AsyncStream(bufferingPolicy: .unbounded) { continuation in
      let id = UUID()

      lock.lock()
      let replay = latest
      let finished = isFinished
      if !finished {
        subscribers[id] = continuation
      }
      lock.unlock()

      // Buffered, not dropped: nobody is iterating yet at this point, and
      // `.unbounded` is what makes that safe. This is the same reasoning
      // `IMAPMailConnectionService` gives for not using `.bufferingNewest(1)`.
      if let replay {
        continuation.yield(replay)
      }
      if finished {
        continuation.finish()
        return
      }

      continuation.onTermination = { [weak self] _ in
        self?.remove(id)
      }
    }
  }

  func publish(_ element: Element) {
    lock.lock()
    latest = element
    let targets = Array(subscribers.values)
    lock.unlock()

    // Yielded outside the lock. `yield` can run a consumer's continuation, and
    // holding a non-recursive `NSLock` across that is how a deadlock gets built.
    for target in targets {
      target.yield(element)
    }
  }

  func finish() {
    lock.lock()
    isFinished = true
    let targets = Array(subscribers.values)
    subscribers.removeAll()
    lock.unlock()

    for target in targets {
      target.finish()
    }
  }

  private func remove(_ id: UUID) {
    lock.lock()
    subscribers[id] = nil
    lock.unlock()
  }
}

/// A `MailConnectionService` whose two streams can be consumed by any number of
/// screens. Everything else forwards untouched.
public final class BroadcastingMailConnectionService: MailConnectionService, @unchecked Sendable {
  private let upstream: any MailConnectionService
  private let stateHub: StreamHub<MailConnectionState>
  private let progressHub: StreamHub<BackfillProgress>
  private let pumps: [Task<Void, Never>]

  public init(upstream: any MailConnectionService) {
    // Built as locals and captured as locals. The pump closures must not touch
    // `self`, which is not fully initialised until `pumps` is assigned.
    let stateHub = StreamHub<MailConnectionState>()
    let progressHub = StreamHub<BackfillProgress>()

    self.upstream = upstream
    self.stateHub = stateHub
    self.progressHub = progressHub

    // Exactly one consumer of each upstream stream, started here and running
    // for the life of the app. That is the "consumes each of these exactly
    // once" the contract asks for.
    self.pumps = [
      Task { [upstream] in
        for await value in upstream.state {
          stateHub.publish(value)
        }
        stateHub.finish()
      },
      Task { [upstream] in
        for await value in upstream.backfillProgress {
          progressHub.publish(value)
        }
        progressHub.finish()
      },
    ]
  }

  deinit {
    pumps.forEach { $0.cancel() }
  }

  /// A **new** stream per access, deliberately. Each screen's `for await` gets
  /// its own subscription; two screens reading this property get two streams,
  /// which is the entire point.
  public var state: AsyncStream<MailConnectionState> { stateHub.stream() }
  public var backfillProgress: AsyncStream<BackfillProgress> { progressHub.stream() }

  public func connect(_ credentials: IMAPCredentials) async throws {
    try await upstream.connect(credentials)
  }

  public func disconnect() async throws {
    try await upstream.disconnect()
  }

  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    try await upstream.syncNow()
  }

  public func startBackfill(months: Int) async throws {
    try await upstream.startBackfill(months: months)
  }
}
