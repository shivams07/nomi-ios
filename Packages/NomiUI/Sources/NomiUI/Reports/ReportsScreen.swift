import Foundation
import NomiCore
import SwiftData
import SwiftUI

/// The Reports/Insights page (U13, v5 new) — the largest of the four new
/// screens. Calendar-month vs financial-year toggle drives every figure via
/// `ReportsViewModel`; income-vs-expense trend; category breakdown; CSV
/// export via `ShareLink`.
///
/// Archived accounts are never excluded here (unlike the dashboard's accounts
/// card) — `insightsStore.insights(for:)`/`.transactions(in:)` don't filter
/// by account at all, so this AC ("archiving must not change a number on
/// Reports") holds by construction: this screen simply never calls
/// `accountSummaries(includeArchived:)`.
public struct ReportsScreen: View {
  public let insightsStore: InsightsStore

  /// Never read. `InsightsCache` lives in `NomiApp`, which `NomiUI` cannot
  /// depend on, so the composition root republishes its generation as this
  /// plain `Int` and passes a new value in on every write. SwiftUI
  /// re-invokes `body` when a stored property of a view value changes
  /// regardless of whether `body` reads it — that's what makes this work,
  /// not a coincidence of it being unused. Do not delete it for looking dead.
  public let refreshToken: Int

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  @State private var basis: PeriodBasis
  @State private var anchor: Date
  @State private var exportURL: URL?
  @State private var exportAllTimeURL: URL?
  @State private var exportError = false

  public init(
    insightsStore: InsightsStore,
    initialBasis: PeriodBasis = .calendarMonth,
    initialAnchor: Date = Date(),
    refreshToken: Int = 0
  ) {
    self.insightsStore = insightsStore
    self.refreshToken = refreshToken
    _basis = State(initialValue: initialBasis)
    _anchor = State(initialValue: initialAnchor)
  }

  private var period: InsightPeriod {
    ReportsPeriod.period(basis: basis, anchor: anchor)
  }

  /// `nil` means `insightsStore.insights(for:)` threw — a real fetch error,
  /// not "no transactions this period" (that case still comes back as a
  /// successful, all-zero `PeriodInsights`). The body's fallback branch
  /// reflects that: it reads as a load failure, not an empty state.
  /// `trend` is no longer threaded through here (H1/L6) — it's its own
  /// `Load` below, rendered independently of whether the rest of the period
  /// loaded, so the field is always empty; nothing reads it once `trendModule`
  /// renders straight from `trendLoad` instead of `viewModel.trend`.
  private var viewModel: ReportsViewModel? {
    guard let insights = try? insightsStore.insights(for: period) else { return nil }
    return ReportsViewModelBuilder.make(period: period, insights: insights, trend: [])
  }

  /// A read that failed is not a read that succeeded and found nothing —
  /// reuses `DashboardWiring.Load`, the same distinction the dashboard's own
  /// cards make (H1/L6): `.failed` renders "Couldn't load trend" in the
  /// card's place instead of silently swallowing a store error into an
  /// empty chart the way `viewModel`'s old `(try? …) ?? []` did.
  private var trendLoad: DashboardWiring.Load<[MonthBucket]> {
    do {
      return .loaded(try insightsStore.trend(months: ReportsPeriod.trendMonths(for: basis)))
    } catch {
      return .failed
    }
  }

  /// `LedgerScreen.categoryNamesByID` carries the full explanation: `id`
  /// carries no unique constraint anywhere in NomiCore, so two devices can
  /// insert `Category`/`Account` rows sharing an id before first sync
  /// reconciles them. `uniqueKeysWithValues:` traps on a duplicate key,
  /// which is exactly the H1 crash; `uniquingKeysWith:` doesn't.
  private var categoryNames: [UUID: String] {
    Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }

  private var accountNames: [UUID: String] {
    Dictionary(accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardToCard) {
        periodSelector
        if let viewModel {
          summarySection(viewModel)
          trendModule
          ReportsCategoryBreakdownCard(slices: viewModel.categories)
          exportButton
        } else {
          Text("Couldn't load report data")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
        // Independent of `viewModel`/`period` on purpose — a one-off,
        // user-initiated whole-ledger read through `.allTime` (acceptable
        // unlike the dashboard's per-render one, F2) works whether or not
        // the current period's figures loaded. A second button, not a mode.
        exportAllTimeButton
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Reports")
    .alert("Could not export CSV", isPresented: $exportError) {
      Button("OK", role: .cancel) {}
    }
  }

  private var periodSelector: some View {
    HStack(spacing: NomiSpacing.sm) {
      Button {
        anchor = ReportsPeriod.shiftedAnchor(anchor, basis: basis, by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .foregroundStyle(NomiColor.textSecondary)
      }
      Text(ReportsPeriod.label(for: period))
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        anchor = ReportsPeriod.shiftedAnchor(anchor, basis: basis, by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.textSecondary)
      }
      NomiSegmentedPill(basis: $basis)
    }
  }

  private func summarySection(_ viewModel: ReportsViewModel) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack {
        summaryFigure(label: "Received", amountMinor: viewModel.creditMinor, delta: viewModel.creditDelta)
        Spacer(minLength: NomiSpacing.sm)
        summaryFigure(label: "Spent", amountMinor: viewModel.debitMinor, delta: viewModel.debitDelta)
      }
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRaised)
    .nomiCornerRadius(NomiRadius.card)
  }

  private func summaryFigure(label: String, amountMinor: Int, delta: ReportsDelta.Result?) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(label)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      Text(NomiFormatters.amountString(minor: amountMinor))
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 20))
        .foregroundStyle(NomiColor.textPrimary)
      if let delta {
        Text("\(delta.isIncrease ? "▲" : "▼") \(ReportsDelta.percentText(delta.percent)) vs last period")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      } else {
        Text("No prior period to compare")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  @ViewBuilder
  private var trendModule: some View {
    switch trendLoad {
    case .loaded(let trend):
      ReportsTrendCard(trend: trend)
    case .failed:
      Text("Couldn't load trend")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  @ViewBuilder
  private var exportButton: some View {
    if let exportURL {
      ShareLink(item: exportURL) {
        Label("Export CSV", systemImage: "square.and.arrow.up")
      }
    } else {
      Button {
        exportURL = writeExport(for: period)
      } label: {
        Label("Export CSV", systemImage: "square.and.arrow.up")
      }
    }
  }

  @ViewBuilder
  private var exportAllTimeButton: some View {
    if let exportAllTimeURL {
      ShareLink(item: exportAllTimeURL) {
        Label("Export all time", systemImage: "square.and.arrow.up")
      }
    } else {
      Button {
        exportAllTimeURL = writeExport(for: .allTime)
      } label: {
        Label("Export all time", systemImage: "square.and.arrow.up")
      }
    }
  }

  /// Shared by both export buttons; each keeps its own `@State` URL so
  /// tapping one doesn't clobber the other's `ShareLink`. Note:
  /// `ReportsCSVExport.write` (not owned by this unit) tracks only one
  /// "last written file" across every call regardless of period, so writing
  /// one export after the other still deletes the first one's file on disk
  /// even though both `@State` URLs remain set — a pre-existing limitation
  /// of that single tracker, not something this fix touches.
  private func writeExport(for exportPeriod: InsightPeriod) -> URL? {
    guard let transactions = try? insightsStore.transactions(in: exportPeriod) else {
      exportError = true
      return nil
    }
    let names = CSVNameMaps(categories: categoryNames, accounts: accountNames)
    guard let url = try? ReportsCSVExport.write(transactions, names: names, periodLabel: ReportsPeriod.label(for: exportPeriod)) else {
      exportError = true
      return nil
    }
    return url
  }
}

/// Manual conformance because `InsightsStore` is an `AnyObject` protocol,
/// not an `Equatable` one — identity stands in for value equality there.
/// Exists so a test can assert that two otherwise-identical view values
/// differing only in `refreshToken` compare as different.
extension ReportsScreen: Equatable {
  public static func == (lhs: ReportsScreen, rhs: ReportsScreen) -> Bool {
    lhs.insightsStore === rhs.insightsStore && lhs.refreshToken == rhs.refreshToken
  }
}

private let previewAnchor = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 15))!

/// A fresh in-memory container per call, just to give the new `@Query`s
/// something to bind to in the canvas — `ReportsPreviewSupport`'s category
/// fixtures live behind `FakeInsightsStore`, not a `ModelContainer`, and
/// none of these previews render category/account names directly (they only
/// feed the export button's CSV, off-screen), so an empty store is enough.
@MainActor
private func reportsCSVExportPreviewContainer() -> ModelContainer {
  try! ModelContainer(
    for: Schema([NomiCore.Category.self, NomiCore.Account.self]),
    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
  )
}

#Preview("Reports — calendar month, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.dark)
}

#Preview("Reports — financial year, same underlying data, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .financialYear,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.dark)
}

#Preview("Reports — 3 months of data, 3 trend bars, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 3, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.dark)
}

#Preview("Reports — zero data, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 0, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.dark)
}

/// `ReportsPreviewSupport` isn't in this unit's file list, so this stays
/// local rather than adding a throwing mode there — same "small file-local
/// throwing fake" pattern `error-surfacing-screens` used for its own
/// failed-load previews. Delegates everything except `trend` to a real
/// preview store so the rest of the screen still renders normally.
@MainActor
private final class TrendFailingInsightsStore: InsightsStore {
  private let base: InsightsStore
  init(wrapping base: InsightsStore) { self.base = base }
  func insights(for period: InsightPeriod) throws -> PeriodInsights { try base.insights(for: period) }
  func trend(months: Int) throws -> [MonthBucket] { throw PreviewLoadError.forcedFailure }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { try base.accountSummaries(includeArchived: includeArchived) }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { try base.budgetProgress(year: year, month: month) }
  // `Transaction` alone is ambiguous with `SwiftUI.Transaction` in a file that
  // imports both — the same collision flagged repeatedly elsewhere in NomiUI.
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { try base.transactions(in: period) }
  func recentTransactions(limit: Int) throws -> [NomiCore.Transaction] { try base.recentTransactions(limit: limit) }
}

private enum PreviewLoadError: Error {
  case forcedFailure
}

#Preview("Reports — trend failed to load, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: TrendFailingInsightsStore(wrapping: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor)),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.dark)
}

#Preview("Reports — accessibility 3, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
