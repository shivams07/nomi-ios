import Foundation

/// Thrown when work has not finished, or a stream has not yielded, within its deadline.
struct TestTimeout: Error, Equatable {
  let seconds: Double
}

/// Runs `work`; throws `TestTimeout` if it has not finished in `seconds`. Returns at the deadline
/// even when `work` ignores cancellation: the work is cancelled and abandoned, never awaited.
///
/// Not a task group. A group waits for every child before it returns, so a child that ignores
/// cancellation holds the caller for ever. That is the hang this exists to stop.
func withTestTimeout<T: Sendable>(
  seconds: Double = 5,
  _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
    let gate = OnceGate()
    let workerBox = TaskBox()
    let timerBox = TaskBox()

    let worker = Task {
      do {
        let value = try await work()
        if gate.claim() {
          timerBox.cancel()
          continuation.resume(returning: value)
        }
      } catch {
        if gate.claim() {
          timerBox.cancel()
          continuation.resume(throwing: error)
        }
      }
    }
    workerBox.set(worker)

    let timer = Task {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      if gate.claim() {
        workerBox.cancel()
        continuation.resume(throwing: TestTimeout(seconds: seconds))
      }
    }
    timerBox.set(timer)
  }
}

/// The first `count` elements of `stream`, under `withTestTimeout`. Returns fewer if the stream
/// finishes first.
func collect<Element: Sendable>(
  _ stream: AsyncStream<Element>, count: Int, seconds: Double = 5
) async throws -> [Element] {
  try await withTestTimeout(seconds: seconds) {
    var out: [Element] = []
    for await element in stream.prefix(count) { out.append(element) }
    return out
  }
}

/// Lets exactly one half of `withTestTimeout` (the work, or the deadline) settle the continuation.
private final class OnceGate: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  /// True for the first caller only.
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !claimed else { return false }
    claimed = true
    return true
  }
}

/// A task handle set after the task is created, so each half of the race can cancel the other.
private final class TaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Void, Never>?

  func set(_ task: Task<Void, Never>) {
    lock.lock()
    defer { lock.unlock() }
    self.task = task
  }

  func cancel() {
    lock.lock()
    let current = task
    lock.unlock()
    current?.cancel()
  }
}
