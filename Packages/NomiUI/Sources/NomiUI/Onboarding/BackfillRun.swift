import Foundation
import NomiCore
import Observation

/// The Backfill screen's scan state and actions, outside the view (T2b), so plain
/// XCTest can drive them with a spy service. The view owns one through `@State`.
/// Copy, layout and the lifecycle rules are unchanged from `BackfillScreen`.
@Observable @MainActor final class BackfillRun {
  /// What the screen does after a control is tapped. `.finish` leaves onboarding.
  enum Outcome: Equatable { case stay, finish }

  @ObservationIgnored let service: MailConnectionService
  @ObservationIgnored let months: Int

  private(set) var progress = BackfillProgress(scanned: 0, total: 0, created: 0)
  private(set) var isCancelled = false
  private(set) var didFail = false
  private(set) var completionSummary: SyncSummary?
  /// The scan in flight, or the one a cancel paused. Nil after a failure.
  private(set) var task: Task<Void, Never>?

  init(service: MailConnectionService, months: Int) {
    self.service = service
    self.months = months
  }

  /// Where the scan stands. Derived from this model's own state, so the screen
  /// and the tests read the same answer.
  var phase: BackfillPhase {
    if completionSummary != nil { return .completed }
    if didFail { return .failed }
    if isCancelled { return .cancelled }
    if task != nil { return .running }
    return .notStarted
  }

  var controls: BackfillControls { BackfillControls.forPhase(phase) }

  func receive(_ update: BackfillProgress) {
    progress = update
  }

  func appear() {
    if BackfillLifecycle.shouldStartOnAppear(phase: phase) {
      start()
    }
  }

  func perform(_ control: BackfillControl) -> Outcome {
    switch control {
    case .cancel:
      cancel()
      return .stay
    case .resume, .retry:
      start()
      return .stay
    case .done:
      return .finish
    }
  }

  /// Resume and Retry come here. A cancelled scan can still be winding down at
  /// its next batch boundary, so the new one waits for it: the service never
  /// sees two scans at once (X14).
  @discardableResult
  func start() -> Task<Void, Never> {
    isCancelled = false
    didFail = false
    let previous = task
    previous?.cancel()
    let next = BackfillSchedule.next(after: previous) { [self] in
      do {
        completionSummary = try await BackfillActions.scan(using: service, months: months)
      } catch {
        // A cancel the user asked for is a pause, not a failure, whatever
        // error the service surfaces on the way out.
        guard !Task.isCancelled, !isCancelled else { return }
        task = nil
        didFail = true
      }
    }
    task = next
    return next
  }

  func cancel() {
    task?.cancel()
    isCancelled = true
  }
}
