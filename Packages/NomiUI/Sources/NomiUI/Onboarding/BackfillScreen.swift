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

  /// The line under a cancelled scan: how many transactions the scan had found.
  static func cancelledText(created: Int) -> String {
    String(localized: "\(created) transactions found so far. You can pick this up any time.", bundle: .module)
  }
}

/// Starts a scan after the one before it has finished (R5e, X14). Pulled out of
/// `BackfillScreen.start()` so the rule is testable without a view.
enum BackfillSchedule {
  static func next(after previous: Task<Void, Never>?, _ scan: @escaping () async -> Void) -> Task<Void, Never> {
    Task {
      await previous?.value
      guard !Task.isCancelled else { return }
      await scan()
    }
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

/// The app's first impression, drawn as the full-bleed Backfill moment (I-9
/// gradient, artboard "First scan", `Backfill.dc.html`). The address being read,
/// the found count, a 10 pt bar, the caption and up to three glass rows per
/// account; one control per state: never two white primaries.
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
  @Environment(\.nomiInsightsStore) private var insightsStore
  /// The scan's state and actions (T2b). See `BackfillRun`. It holds the service
  /// the screen reads progress and the address from, so there is one source.
  @State private var run: BackfillRun
  /// The address the mail is read from, for "Scanning <address>". Nil until the
  /// connection reports it.
  @State private var address: String?
  /// The account rows and the Need-a-look row, read from the insights store on
  /// each progress tick. Empty when there is no store, which hides them.
  @State private var rows: [(title: String, detail: String)] = []

  public init(
    mailConnectionService: MailConnectionService,
    months: Int = 6,
    onFinish: (() -> Void)? = nil
  ) {
    self.mailConnectionService = mailConnectionService
    self.months = months
    self.onFinish = onFinish
    _run = State(initialValue: BackfillRun(service: mailConnectionService, months: months))
  }

  public var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          navRow
            .frame(height: NomiSpacing.navRowHeight)
          scanningLine
            .padding(.top, 14)
          countLine
            .padding(.top, 24)
          if run.phase != .cancelled {
            foundLine
              .padding(.top, NomiSpacing.xxs)
          }
          bar
            .padding(.top, 26)
          caption
            .padding(.top, NomiSpacing.xs)
          accountRows
            .padding(.top, 30)
          Spacer(minLength: NomiSpacing.lg)
          controlsView
            .padding(.top, NomiSpacing.md)
        }
        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.bottom, NomiSpacing.lg)
      }
    }
    .background(NomiHeroGradient.moment.ignoresSafeArea())
    .task {
      // Display only. Completion is whatever `startBackfill` returned, not a
      // guess made from the last tick: the stream is a progress bar, and the
      // scan itself is the thing that knows when it finished and what it found.
      // Read from `run.service`, the same service the scan runs on (Lim, PR 199).
      for await update in run.service.backfillProgress {
        run.receive(update)
        refreshRows()
      }
    }
    .task {
      for await state in run.service.state {
        if case .connected(let connected, _) = state {
          address = connected
        }
      }
    }
    .onAppear {
      run.appear()
      refreshRows()
    }
    .onChange(of: run.phase) { _, _ in
      refreshRows()
    }
    #if os(iOS)
    .toolbar(.hidden, for: .navigationBar)
    .statusBarHidden(BackfillChrome.hidesStatusBar)
    #endif
  }

  // MARK: - Layout

  /// The nav row keeps the leave text at the top trailing edge, 44 high. It is
  /// empty on the Done frame, where the white Done is the exit.
  private var navRow: some View {
    HStack {
      Spacer()
      if run.controls.showsLeave {
        Button("Done") { onFinish?() }
          .nomiTextStyle(.navActionStrong)
          .foregroundStyle(NomiColor.heroText)
          .frame(minWidth: NomiSpacing.minTarget, minHeight: NomiSpacing.minTarget)
          .contentShape(Rectangle())
      }
    }
  }

  /// "Scanning <address>" at 14 Medium. The phase copy replaces it once the scan
  /// stops, and the address is left out until the connection has named it.
  private var scanningLine: some View {
    Text(scanningText)
      .nomiTextStyle(.chip)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The found count at 46 SemiBold, formatted with the locale's grouping.
  private var countLine: some View {
    Text(found, format: .number)
      .nomiTextStyle(.heroAmount)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentTransition(.numericText(value: Double(found)))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: found)
  }

  private var foundLine: some View {
    Text(BackfillDisplay.foundLine(created: found))
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.heroText)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// 10 pt: the scanned share of the total. The completed frame is full.
  private var bar: some View {
    BackfillBar(fraction: BackfillMath.fraction(shownProgress), animated: !reduceMotion)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Scanned")
      .accessibilityValue("\(shownProgress.scanned) of \(shownProgress.total)")
  }

  /// The caption under the bar: what the scan is reading, or why it stopped, or
  /// what the finished scan matched.
  @ViewBuilder
  private var caption: some View {
    switch run.phase {
    case .notStarted, .running:
      Text(BackfillDisplay.captionLine(months: months))
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    case .cancelled:
      Text(BackfillLifecycle.cancelledText(created: run.progress.created))
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    case .failed:
      Text("Something went wrong while reading your mail. Try again.")
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    case .completed:
      if let completionSummary = run.completionSummary {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          ForEach(BackfillCompletionSummary.detailLines(for: completionSummary), id: \.self) { line in
            Text(line)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.heroTextSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  /// Up to three glass rows, one per account and then the Need-a-look row. Hidden
  /// when there are none, which includes the case where the store is nil.
  @ViewBuilder
  private var accountRows: some View {
    if !rows.isEmpty {
      VStack(spacing: NomiSpacing.xs) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          accountRow(title: row.title, detail: row.detail)
        }
      }
    }
  }

  private func accountRow(title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
      Text(title)
        .nomiTextStyle(.chipSelected)
        .foregroundStyle(NomiColor.heroText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Text(detail)
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.heroTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiGlass(.heroControl, in: RoundedRectangle(cornerRadius: NomiRadius.inset, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var controlsView: some View {
    VStack(spacing: NomiSpacing.sm) {
      if let secondary = run.controls.secondary {
        heroButton(secondary)
      }
      if let primary = run.controls.primary {
        heroButton(primary)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// DEC-09: 200 x 52 capsule. The label fills the width so the capsule takes
  /// the frame's width, not the text's.
  private func heroButton(_ control: BackfillControl) -> some View {
    Button {
      if run.perform(control) == .finish { onFinish?() }
    } label: {
      Text(title(for: control))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(NomiHeroButtonStyle(control.kind))
    .frame(width: 200)
  }

  // MARK: - Copy and values per phase

  /// The completed frame's white primary reads "Continue to Nomi" (artboard
  /// "First scan"). It is the same `.done` control, so only its label changes here.
  private func title(for control: BackfillControl) -> String {
    if run.phase == .completed, control == .done {
      return "Continue to Nomi"
    }
    return control.title
  }

  private var scanningText: String {
    switch run.phase {
    case .notStarted, .running:
      guard let address else { return "Scanning your mail" }
      return "Scanning \(address)"
    case .cancelled: return "Scan paused"
    case .completed: return "All caught up"
    case .failed: return "Couldn’t finish the scan"
    }
  }

  /// The count and the bar read from the completed summary once the scan returns,
  /// so the Done frame matches what the scan reported, not the last stream tick.
  private var shownProgress: BackfillProgress {
    if let completionSummary = run.completionSummary {
      return BackfillProgress(
        scanned: completionSummary.scanned,
        total: completionSummary.scanned,
        created: completionSummary.created
      )
    }
    return run.progress
  }

  private var found: Int { shownProgress.created }

  /// Reads the account rows and the review count from the insights store. A read
  /// that throws counts as nothing to show, so the screen never fails on it.
  private func refreshRows() {
    guard let insightsStore else {
      rows = []
      return
    }
    let summaries = (try? insightsStore.accountSummaries(includeArchived: false)) ?? []
    let needsReview = (try? insightsStore.needsReviewCountAllTime()) ?? 0
    rows = BackfillDisplay.rows(summaries: summaries, needsReview: needsReview)
  }
}

/// The scan's bar: a 10 pt capsule, white at 28% under a white fill (artboard
/// "First scan"). The fill is the scanned share, clamped to the track.
private struct BackfillBar: View {
  let fraction: Double
  let animated: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(NomiColor.heroText.opacity(0.28))
        Capsule()
          .fill(NomiColor.heroText)
          .frame(width: proxy.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 10)
    .animation(animated ? .easeOut(duration: 0.3) : nil, value: fraction)
  }
}

#Preview("Backfill — scanning") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 340, total: 1200, created: 58)
  ))
}

#Preview("Backfill — scanning with accounts") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 340, total: 1200, created: 214)
  ))
  .environment(\.nomiInsightsStore, FakeInsightsStore())
}

#Preview("Backfill — complete") {
  BackfillScreen(mailConnectionService: FixedBackfillFakeMailConnectionService(
    progress: BackfillProgress(scanned: 1200, total: 1200, created: 91)
  ))
}

#Preview("Backfill — failed") {
  BackfillScreen(mailConnectionService: AlwaysFailingMailConnectionService())
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
