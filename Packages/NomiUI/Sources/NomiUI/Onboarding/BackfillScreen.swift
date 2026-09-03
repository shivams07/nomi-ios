import NomiCore
import NomiPreview
import SwiftUI

/// Where the scan stands, derived from `BackfillScreen`'s own `@State` so the
/// appear-triggered decision below can be tested without a view or a `Task`.
enum BackfillPhase: Equatable {
  case notStarted
  case running
  case cancelled
  case completed
}

/// The rule that lets `.onDisappear`'s cancel go away without silently
/// double-starting the scan: appearing only kicks off `startBackfill` from
/// `.notStarted`. Leaving mid-scan and coming back finds `.running` and
/// does nothing — the in-flight task (never cancelled now) is still the one
/// driving `backfillProgress`. A cancelled scan stays paused until the user
/// taps Resume; it does not silently resume just because the screen
/// reappeared.
enum BackfillLifecycle {
  static func shouldStartOnAppear(phase: BackfillPhase) -> Bool {
    phase == .notStarted
  }
}

/// The app's first impression (U7 notes: "the hero screen"). Determinate bar,
/// live scanned/found counts, rows animating in as they land — never a
/// spinner. `BackfillProgress` carries aggregate counts only, no per-
/// transaction rows to render individually, so "rows animating in" is
/// expressed as the found-count animating with `.numericText` each time it
/// changes (same primitive `HeroTotalCard` uses for its count-up) rather than
/// a literal list — there is no per-row data in this contract to list.
/// Cancellable and resumable through structured concurrency: there is no
/// cancel/resume method on `MailConnectionService`, so this screen owns a
/// local `Task` wrapping `startBackfill(months:)` and cancels/re-creates it
/// rather than asking the contract for something it doesn't declare.
public struct BackfillScreen: View {
  public let mailConnectionService: MailConnectionService
  public let months: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress = BackfillProgress(scanned: 0, total: 0, created: 0)
  @State private var isCancelled = false
  @State private var completionSummary: SyncSummary?
  @State private var backfillTask: Task<Void, Never>?

  public init(mailConnectionService: MailConnectionService, months: Int = 6) {
    self.mailConnectionService = mailConnectionService
    self.months = months
  }

  private var currentPhase: BackfillPhase {
    if completionSummary != nil { return .completed }
    if isCancelled { return .cancelled }
    if backfillTask != nil { return .running }
    return .notStarted
  }

  public var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: NomiSpacing.lg) {
          Spacer(minLength: NomiSpacing.lg)
          if let completionSummary {
            completionView(completionSummary)
          } else if isCancelled {
            cancelledView
          } else {
            scanningView
          }
          Spacer(minLength: NomiSpacing.lg)
        }
        .frame(minHeight: proxy.size.height)
        .padding(NomiSpacing.screenGutter)
      }
    }
    .background(NomiColor.surfaceCanvas)
    .task {
      for await update in mailConnectionService.backfillProgress {
        progress = update
        if BackfillMath.isComplete(update) {
          completionSummary = try? await mailConnectionService.syncNow()
        }
      }
    }
    .onAppear {
      if BackfillLifecycle.shouldStartOnAppear(phase: currentPhase) {
        start()
      }
    }
  }

  private var scanningView: some View {
    VStack(spacing: NomiSpacing.md) {
      Text("Getting your transactions")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(NomiColor.surface)
          Capsule(style: .continuous)
            .fill(NomiColor.progressTrackFill)
            .frame(width: proxy.size.width * BackfillMath.fraction(progress))
        }
      }
      .frame(height: NomiSpacing.sm)
      .clipShape(Capsule(style: .continuous))
      Text("\(progress.scanned) of \(progress.total) scanned — \(progress.created) found")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .contentTransition(.numericText(value: Double(progress.created)))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress.created)
      Button("Cancel", role: .destructive) { cancel() }
        .padding(.top, NomiSpacing.sm)
    }
  }

  private var cancelledView: some View {
    VStack(spacing: NomiSpacing.md) {
      Text("Scan paused")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("\(progress.created) transactions found so far. You can pick this up any time.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      Button("Resume") { resume() }
    }
  }

  private func completionView(_ summary: SyncSummary) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("All caught up")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      ForEach(BackfillCompletionSummary.lines(for: summary), id: \.self) { line in
        Text(line)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textSecondary)
      }
    }
  }

  private func start() {
    isCancelled = false
    backfillTask = Task {
      try? await mailConnectionService.startBackfill(months: months)
    }
  }

  private func cancel() {
    backfillTask?.cancel()
    isCancelled = true
  }

  private func resume() {
    start()
  }
}

#Preview("Backfill — scanning, dark") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 340, total: 1200, created: 58)
  ))
  .preferredColorScheme(.dark)
}

#Preview("Backfill — complete, dark") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 1200, total: 1200, created: 91)
  ))
  .preferredColorScheme(.dark)
}
