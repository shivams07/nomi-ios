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
  case failed
}

/// The rule that lets `.onDisappear`'s cancel go away without silently
/// double-starting the scan: appearing only kicks off `startBackfill` from
/// `.notStarted`. Leaving mid-scan and coming back finds `.running` and
/// does nothing — the in-flight task (never cancelled now) is still the one
/// driving `backfillProgress`. A cancelled scan stays paused until the user
/// taps Resume, and a failed one until the user taps Retry; neither restarts
/// just because the screen reappeared.
enum BackfillLifecycle {
  static func shouldStartOnAppear(phase: BackfillPhase) -> Bool {
    phase == .notStarted
  }
}

/// The scan, pulled out so it is spy-testable in the same shape as
/// `SettingsActions.rescan`: it must call `startBackfill(months:)` and nothing
/// else — specifically never `syncNow()`. The screen used to end its progress
/// loop with a full second sync purely to obtain a `SyncSummary` to render,
/// which re-fetched and re-ingested everything the backfill had just done. The
/// backfill's own return value is that summary, so the completion card now
/// reports the work that was actually watched rather than a second opinion
/// about it.
enum BackfillActions {
  @discardableResult
  static func scan(using service: MailConnectionService, months: Int) async throws -> SyncSummary {
    try await service.startBackfill(months: months)
  }
}

/// The app's first impression (U7 notes: "the hero screen"), redrawn as the
/// full-bleed Backfill moment (DEC-09, `Backfill.dc.html`, `BackfillDone.dc.html`).
/// A progress ring, a count, and one control per state: never two white primaries.
///
/// Cancelling pauses the scan (Resume picks it up); it is not destructive, so it
/// is glass, not red. Leaving with "Done" while a scan runs does not stop it:
/// `BackfillBanner` shows it after this screen is gone. There is no
/// cancel/resume method on `MailConnectionService`, so this screen owns a local
/// `Task` wrapping `startBackfill(months:)` and cancels/re-creates it.
public struct BackfillScreen: View {
  public let mailConnectionService: MailConnectionService
  public let months: Int
  /// Leaves onboarding. Called by the leave text while a scan runs or is
  /// paused or failed, and by the white Done once it completes.
  public var onFinish: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress = BackfillProgress(scanned: 0, total: 0, created: 0)
  @State private var isCancelled = false
  @State private var didFail = false
  @State private var completionSummary: SyncSummary?
  @State private var backfillTask: Task<Void, Never>?

  public init(
    mailConnectionService: MailConnectionService,
    months: Int = 6,
    onFinish: (() -> Void)? = nil
  ) {
    self.mailConnectionService = mailConnectionService
    self.months = months
    self.onFinish = onFinish
  }

  private var currentPhase: BackfillPhase {
    if completionSummary != nil { return .completed }
    if didFail { return .failed }
    if isCancelled { return .cancelled }
    if backfillTask != nil { return .running }
    return .notStarted
  }

  private var controls: BackfillControls {
    BackfillControls.forPhase(currentPhase)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        navRow
          .frame(height: NomiSpacing.navRowHeight)
        heading
          .padding(.top, 14)
        ring
          .padding(.top, 104)
        countLine
          .padding(.top, 24)
        detail
        controlsView
          .padding(.top, 28)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.lg)
    }
    .background(NomiHeroGradient.moment.ignoresSafeArea())
    .task {
      // Display only. Completion is whatever `startBackfill` returned, not a
      // guess made from the last tick: the stream is a progress bar, and the
      // scan itself is the thing that knows when it finished and what it found.
      for await update in mailConnectionService.backfillProgress {
        progress = update
      }
    }
    .onAppear {
      if BackfillLifecycle.shouldStartOnAppear(phase: currentPhase) {
        start()
      }
    }
    #if os(iOS)
    .toolbar(.hidden, for: .navigationBar)
    #endif
  }

  // MARK: - Layout

  /// The nav row keeps the leave text at the top trailing edge, 44 high. It is
  /// empty on the Done frame, where the white Done is the exit.
  private var navRow: some View {
    HStack {
      Spacer()
      if controls.showsLeave {
        Button("Done") { onFinish?() }
          .nomiTextStyle(.navActionStrong)
          .foregroundStyle(NomiColor.heroText)
          .frame(minWidth: NomiSpacing.minTarget, minHeight: NomiSpacing.minTarget)
          .contentShape(Rectangle())
      }
    }
  }

  private var heading: some View {
    Text(titleText)
      .nomiTextStyle(.heroTitle)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var ring: some View {
    BackfillRing(
      fraction: ringFraction,
      symbol: ringSymbol,
      symbolColor: NomiColor.heroText,
      animated: !reduceMotion
    )
    .accessibilityHidden(true)
  }

  private var countLine: some View {
    Text(countText)
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.heroText)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .contentTransition(.numericText(value: Double(countValue.found)))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: countValue.found)
  }

  @ViewBuilder
  private var detail: some View {
    switch currentPhase {
    case .completed:
      if let completionSummary {
        VStack(spacing: NomiSpacing.xxs) {
          ForEach(BackfillCompletionSummary.detailLines(for: completionSummary), id: \.self) { line in
            Text(line)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.heroTextSecondary)
              .multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NomiSpacing.xs)
      }
    case .cancelled:
      Text("\(progress.created) transactions found so far. You can pick this up any time.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, NomiSpacing.xs)
    case .failed:
      Text("Something went wrong while reading your mail. Try again.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, NomiSpacing.xs)
    case .notStarted, .running:
      EmptyView()
    }
  }

  private var controlsView: some View {
    VStack(spacing: NomiSpacing.sm) {
      if let secondary = controls.secondary {
        heroButton(secondary)
      }
      if let primary = controls.primary {
        heroButton(primary)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// DEC-09: 200 x 52 capsule. The label fills the width so the capsule takes
  /// the frame's width, not the text's.
  private func heroButton(_ control: BackfillControl) -> some View {
    Button {
      perform(control)
    } label: {
      Text(control.title)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(NomiHeroButtonStyle(control.kind))
    .frame(width: 200)
  }

  // MARK: - Copy and values per phase

  private var titleText: String {
    switch currentPhase {
    case .notStarted, .running: return "Getting your transactions"
    case .cancelled: return "Scan paused"
    case .completed: return "All caught up"
    case .failed: return "Couldn’t finish the scan"
    }
  }

  private var ringFraction: Double {
    switch currentPhase {
    case .completed: return 1
    case .notStarted, .running, .cancelled, .failed: return BackfillMath.fraction(progress)
    }
  }

  private var ringSymbol: String {
    switch currentPhase {
    case .completed: return "checkmark"
    case .failed: return "exclamationmark.circle"
    case .notStarted, .running, .cancelled: return "envelope"
    }
  }

  /// The count line reads from the completed summary once the scan returns, so
  /// the Done frame matches what the scan reported, not the last stream tick.
  private var countValue: (scanned: Int, total: Int, found: Int) {
    if let completionSummary {
      return (completionSummary.scanned, completionSummary.scanned, completionSummary.created)
    }
    return (progress.scanned, progress.total, progress.created)
  }

  private var countText: String {
    let value = countValue
    return "\(value.scanned) of \(value.total) scanned — \(value.found) found"
  }

  // MARK: - Actions

  private func perform(_ control: BackfillControl) {
    switch control {
    case .cancel: cancel()
    case .resume, .retry: start()
    case .done: onFinish?()
    }
  }

  private func start() {
    isCancelled = false
    didFail = false
    backfillTask = Task {
      do {
        completionSummary = try await BackfillActions.scan(
          using: mailConnectionService, months: months)
      } catch {
        // A cancel the user asked for is a pause, not a failure, whatever
        // error the service surfaces on the way out.
        guard !Task.isCancelled, !isCancelled else { return }
        backfillTask = nil
        didFail = true
      }
    }
  }

  private func cancel() {
    backfillTask?.cancel()
    isCancelled = true
  }
}

/// The progress ring: a white track at 22% and a white arc, 12 pt stroke, with
/// a glyph in the centre (`Backfill.dc.html` ring, `BackfillDone.dc.html`).
/// Built here, not `NomiRingGauge`, which is navy and is for the light grounds.
private struct BackfillRing: View {
  let fraction: Double
  let symbol: String
  let symbolColor: Color
  let animated: Bool

  var body: some View {
    ZStack {
      Circle()
        .stroke(NomiColor.heroText.opacity(0.22), lineWidth: 12)
        .padding(6)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0), 1))
        .stroke(NomiColor.heroText, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .padding(6)
        .animation(animated ? .easeOut(duration: 0.3) : nil, value: fraction)
      Image(systemName: symbol)
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .foregroundStyle(symbolColor)
    }
    .frame(width: 200, height: 200)
    .frame(maxWidth: .infinity)
  }
}

#Preview("Backfill — scanning") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 340, total: 1200, created: 58)
  ))
}

#Preview("Backfill — complete") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 1200, total: 1200, created: 91)
  ))
}

private struct BackfillStartFailure: Error {}

/// `startBackfill` always throws, so `.onAppear`'s `start()` lands on the
/// failed frame as soon as the canvas renders — no tap needed to reach it.
private actor AlwaysFailingMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  init() {
    state = AsyncStream { continuation in
      continuation.yield(.connected(address: "shivam@example.com", lastSync: Date()))
    }
    backfillProgress = AsyncStream { _ in }
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  @discardableResult func syncNow() async throws -> SyncSummary { throw BackfillStartFailure() }
  @discardableResult func startBackfill(months: Int) async throws -> SyncSummary {
    throw BackfillStartFailure()
  }
}

#Preview("Backfill — failed") {
  BackfillScreen(mailConnectionService: AlwaysFailingMailConnectionService())
}
