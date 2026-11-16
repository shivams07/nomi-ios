import Foundation
import NomiCore
import SwiftData
import SwiftUI

/// The `.task(id:)` identity of Insights' load (S6). A change of period, of the
/// cache generation or of the retry token reloads both reads once.
private struct ReportsLoadKey: Hashable {
  let period: InsightPeriod
  let refreshToken: Int
  let retryToken: Int
}

/// The Insights tab (the approved Insights artboard; S6). A page header with the
/// period pill, then Spent and Income, Kept, Last 6 months, By category, Top
/// merchants and the CSV export. The screen reads and drives `ReportsModel`,
/// which holds the period state and both reads. Its figures are derived by
/// `ReportsViewModelBuilder`.
///
/// Archived accounts are never excluded here (unlike the dashboard's accounts
/// card). `insightsStore.insights(for:)`/`.transactions(in:)` don't filter by
/// account at all, so this AC ("archiving must not change a number on Reports")
/// holds by construction: this screen never calls `accountSummaries(includeArchived:)`.
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

  /// The period, its basis and anchor, the follow-today rule, the bars' kind and
  /// both reads. The screen holds none of that itself (T2a note).
  @State private var model: ReportsModel
  /// The CSV the export menu just wrote. Presented once, then removed when the
  /// share sheet closes (by the state's setter, not an `onDismiss`).
  @State private var share = ReportsShareState()
  @State private var exportError = false

  /// The bottom reserve for the Insights tab (F3b). 0 on a pushed screen.
  @Environment(\.nomiTabBarReserve) private var tabBarReserve

  public init(
    insightsStore: InsightsStore,
    initialBasis: PeriodBasis = .calendarMonth,
    initialAnchor: Date = Date(),
    refreshToken: Int = 0
  ) {
    self.insightsStore = insightsStore
    self.refreshToken = refreshToken
    _model = State(initialValue: ReportsModel(
      insightsStore: insightsStore,
      basis: initialBasis,
      anchor: initialAnchor
    ))
  }

  private var period: InsightPeriod {
    model.period
  }

  private var basis: PeriodBasis {
    model.basis
  }

  /// Read by `monthlyTrend`. The count lives on the model now.
  private var retryToken: Int {
    model.retryToken
  }

  /// The financial-year read that T2a's wiring tests pin. It reads the same
  /// store method as `ReportsModel.trend`, which is what the bars draw.
  /// `nil` on the calendar basis, which reads no monthly series. A read that
  /// failed is not a read that found nothing, so `.failed` is its own case.
  var monthlyTrend: DashboardWiring.Load<[MonthBucket]>? {
    _ = retryToken
    guard basis == .financialYear else { return nil }
    do {
      return .loaded(try ReportsMonthlyBars.buckets(for: period, store: insightsStore))
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
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        header
        cards
        exportRow
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.xs)
      .padding(.bottom, NomiSpacing.sm)
    }
    // The last row clears the floating tab bar (F3b). A pushed screen gets 0.
    .contentMargins(.bottom, tabBarReserve, for: .scrollContent)
    .background(NomiColor.ground)
    // The title is the page header in the content (artboard Insights), so the bar goes.
    #if os(iOS)
      .toolbar(.hidden, for: .navigationBar)
    #endif
    .alert("Could not export CSV", isPresented: $exportError) {
      Button("OK", role: .cancel) {}
    }
    .sheet(item: $share.item) { item in
      ReportsShareSheet(url: item.url)
    }
    .task(id: ReportsLoadKey(period: period, refreshToken: refreshToken, retryToken: model.retryToken)) {
      model.load()
    }
    .onChange(of: refreshToken) { _, _ in
      model.dayChanged(now: Date())
    }
  }

  // MARK: - Header

  /// The page header (artboard Insights): "Insights" on the left, the period pill
  /// on the right. The pill's menu is Home's shape: a basis picker, a divider,
  /// then the recent periods.
  private var header: some View {
    NomiPageHeader("Insights") {
      NomiPeriodPill(title: ReportsPeriod.label(for: period, calendar: model.calendar), style: .onGround) {
        periodMenu
      }
    }
  }

  @ViewBuilder
  private var periodMenu: some View {
    Picker("Period basis", selection: basisBinding) {
      Text("Calendar month").tag(PeriodBasis.calendarMonth)
      Text("Financial year").tag(PeriodBasis.financialYear)
    }
    Divider()
    ForEach(ReportsPeriod.recentAnchors(basis: basis, now: Date(), calendar: model.calendar), id: \.self) { candidate in
      Button(ReportsPeriod.label(for: ReportsPeriod.period(basis: basis, anchor: candidate, calendar: model.calendar), calendar: model.calendar)) {
        model.pickAnchor(candidate, now: Date())
      }
    }
  }

  /// Changing the basis goes through the model, which follows today again.
  private var basisBinding: Binding<PeriodBasis> {
    Binding(
      get: { model.basis },
      set: { model.setBasis($0, now: Date()) }
    )
  }

  // MARK: - Cards

  /// The cards under the header, in the artboard's order. Each read has its own
  /// failure: the insights read fails its four cards, the monthly read fails the
  /// bars card alone. An empty period keeps the empty state.
  @ViewBuilder
  private var cards: some View {
    if let insights = model.insights {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        switch ReportsBodyPlan.make(basis: basis, transactionCount: insights.loadedValue?.transactionCount) {
        case .loadFailed:
          failedCard("Spent and income didn’t load.")
          failedCard("Kept didn’t load.")
          trendCard
          failedCard("By category didn’t load.")
          failedCard("Top merchants didn’t load.")
        case .empty:
          emptyState
        case .content:
          if let figures = insights.loadedValue {
            populatedCards(ReportsViewModelBuilder.make(period: period, insights: figures, calendar: model.calendar))
          }
        }
      }
    }
  }

  private func failedCard(_ message: String) -> some View {
    NomiLoadFailedCard(message: message) {
      model.retry()
    }
  }

  private func populatedCards(_ figures: ReportsViewModel) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      HStack(alignment: .top, spacing: NomiSpacing.xs) {
        figureTile(label: "Spent", minor: figures.debitMinor, comparison: figures.debitComparison)
        figureTile(label: "Income", minor: figures.creditMinor, comparison: figures.creditComparison)
      }
      ReportsKeptCard(
        isMonth: basis == .calendarMonth,
        keptMinor: ReportsKept.minor(creditMinor: figures.creditMinor, debitMinor: figures.debitMinor),
        creditMinor: figures.creditMinor
      )
      trendCard
      ReportsCategoryBreakdownCard(breakdown: figures.categories, uncategorizedCount: figures.uncategorizedCount)
      ReportsMerchantsCard(merchants: figures.topMerchants)
    }
  }

  /// A total and the comparison line under it. The line is a tag when it fits;
  /// when it does not (the empty-prior copy is long), it wraps as text instead
  /// of truncating. `comparison` is `nil` with no prior period, so no line.
  private func figureTile(label: LocalizedStringKey, minor: Int, comparison: String?) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(label, bundle: .module)
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.inkSecondary)
      NomiAmountText(minor: minor, style: .summaryValue)
      if let comparison {
        ViewThatFits(in: .horizontal) {
          NomiTag(comparison)
          Text(verbatim: comparison)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
    .accessibilityElement(children: .combine)
  }

  /// The bars for the selected period: the six months to the period's month on
  /// the calendar basis, or the financial year's twelve. Tapping a bar opens that
  /// month. The caption is for the current month only.
  @ViewBuilder
  private var trendCard: some View {
    switch model.trend {
    case nil:
      EmptyView()
    case .loaded(let buckets)?:
      ReportsTrendCard(
        title: basis == .calendarMonth ? "Last 6 months" : "This financial year",
        buckets: buckets,
        kind: $model.kind,
        selectedMonth: model.anchor,
        calendar: model.calendar,
        caption: ReportsBars.caption(anchor: model.anchor, now: Date(), calendar: model.calendar)
      ) { bucket in
        model.selectMonth(bucket, now: Date())
      }
    case .failed?:
      failedCard("Monthly figures didn’t load.")
    }
  }

  private var emptyState: some View {
    NomiEmptyState(
      systemImage: "chart.pie",
      title: "No spending yet",
      message: "Insights fill in once transactions arrive."
    )
    .frame(maxWidth: .infinity)
    .padding(.vertical, NomiSpacing.lg)
  }

  // MARK: - Export

  /// One control, two actions. Each tap writes a fresh CSV and opens the share
  /// sheet for it at once (R12b, Y1).
  private var exportRow: some View {
    let name = ReportsPeriod.exportName(for: period, calendar: model.calendar)
    return Menu {
      Button("This period") {
        share(period)
      }
      Button("All time") {
        share(.allTime)
      }
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text(verbatim: String(localized: "Export \(name) as CSV", bundle: .module))
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
        Spacer(minLength: NomiSpacing.xs)
        Image(systemName: "chevron.down")
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
      .nomiCard(padding: EdgeInsets())
    }
  }

  /// Writes the CSV for `exportPeriod` and opens the share sheet on it. A read
  /// or write failure raises the export alert and opens no sheet.
  private func share(_ exportPeriod: InsightPeriod) {
    guard let transactions = try? insightsStore.transactions(in: exportPeriod) else {
      exportError = true
      return
    }
    let names = CSVNameMaps(categories: categoryNames, accounts: accountNames)
    do {
      let url = try ReportsCSVExport.write(transactions, names: names, periodLabel: ReportsPeriod.label(for: exportPeriod, calendar: model.calendar))
      share.item = ReportsShareItem(url: url)
    } catch {
      exportError = true
    }
  }
}

/// The FY bars' source: `monthlyTrend(for:)` for the selected period, one bucket
/// per month, zero-filled. Its own function so a test can pin that the bars read
/// it, and not `trend(months:)` (R12b, Y2).
@MainActor
enum ReportsMonthlyBars {
  static func buckets(for period: InsightPeriod, store: InsightsStore) throws -> [MonthBucket] {
    try store.monthlyTrend(for: period)
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

#Preview("Insights · calendar month") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.light)
}

#Preview("Insights · financial year, same data") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .financialYear,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.light)
}

#Preview("Insights · 3 months of data") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 3, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.light)
}

#Preview("Insights · no transactions") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 0, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.light)
}

/// `ReportsPreviewSupport` isn't in this unit's file list, so this stays
/// local rather than adding a throwing mode there — same "small file-local
/// throwing fake" pattern `error-surfacing-screens` used for its own
/// failed-load previews. Delegates everything except `monthlyTrend(for:)` to a
/// real preview store so the rest of the screen still renders normally.
@MainActor
private final class TrendFailingInsightsStore: InsightsStore {
  private let base: InsightsStore
  init(wrapping base: InsightsStore) { self.base = base }
  func insights(for period: InsightPeriod) throws -> PeriodInsights { try base.insights(for: period) }
  func trend(months: Int) throws -> [MonthBucket] { try base.trend(months: months) }
  func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket] { throw PreviewLoadError.forcedFailure }
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

#Preview("Insights · monthly trend failed") {
  NavigationStack {
    ReportsScreen(
      insightsStore: TrendFailingInsightsStore(wrapping: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor)),
      initialBasis: .financialYear,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .preferredColorScheme(.light)
}

#Preview("Insights · accessibility 3") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .modelContainer(reportsCSVExportPreviewContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
