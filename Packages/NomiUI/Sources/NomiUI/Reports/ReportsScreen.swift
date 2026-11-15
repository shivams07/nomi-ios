import Foundation
import NomiCore
import SwiftData
import SwiftUI

/// The Insights page (the approved Insights artboard; the Reports screen before
/// the restyle). The period pill sits in the nav row's trailing slot. Below the
/// large title: the Spent / Received card, the day bars (or the month bars on
/// the financial-year basis), the category donut, top merchants, and one Export
/// row whose menu holds the two CSV actions. The screen's figures all come from
/// `ReportsViewModel`.
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
  /// `true` until the user picks a period, and again when a picked period
  /// contains today. Decides whether a refresh moves `anchor` to now (R12b, Y1).
  @State private var followsToday = true
  /// The CSV the export menu just wrote. Presented once, then removed when the
  /// share sheet closes (by the state's setter, not an `onDismiss`).
  @State private var share = ReportsShareState()
  @State private var exportError = false
  /// Bumped by a load-failed card's Retry, so the body reads the store again.
  @State private var retryToken = 0

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
  /// successful, all-zero `PeriodInsights`). The body shows a load-failed card
  /// for that case, never the empty state.
  private var viewModel: ReportsViewModel? {
    _ = retryToken
    guard let insights = try? insightsStore.insights(for: period) else { return nil }
    return ReportsViewModelBuilder.make(period: period, insights: insights, trend: [])
  }

  /// The financial-year basis draws one bar per month of the selected year
  /// (`InsightsStore.monthlyTrend(for:)`, zero-filled, R12b Y2). A calendar
  /// month draws its daily bars from the period itself, so it never reads the
  /// monthly series. A read that failed is not a read that found nothing, so
  /// `.failed` is its own case.
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

  /// The bottom reserve for the Insights tab (F3b). 0 on a pushed screen.
  @Environment(\.nomiTabBarReserve) private var tabBarReserve

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        switch ReportsBodyPlan.make(basis: basis, transactionCount: viewModel?.transactionCount) {
        case .loadFailed:
          NomiLoadFailedCard(message: "Insights didn’t load.") {
            retryToken += 1
          }
        case .empty:
          emptyState
        case .content:
          if let viewModel {
            summaryCard(viewModel)
            barsCard(viewModel)
            ReportsCategoryBreakdownCard(slices: viewModel.categories)
            TopMerchantsCard(merchants: viewModel.topMerchants)
          }
        }
        // Independent of `viewModel`/`period` on purpose — a one-off,
        // user-initiated whole-ledger read through `.allTime` (acceptable
        // unlike the dashboard's per-render one, F2) works whether or not
        // the current period's figures loaded.
        exportRow
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.xs)
      .padding(.bottom, NomiSpacing.sm)
    }
    // The Export row clears the floating tab bar in both orientations (Andrews, PR #194).
    .contentMargins(.bottom, tabBarReserve, for: .scrollContent)
    .background(NomiColor.ground)
    .navigationTitle("Insights")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        periodPill
      }
    }
    .alert("Could not export CSV", isPresented: $exportError) {
      Button("OK", role: .cancel) {}
    }
    .sheet(item: $share.item) { item in
      ReportsShareSheet(url: item.url)
    }
    .onChange(of: refreshToken) { _, _ in
      anchor = PeriodAnchorPolicy.anchorAfterRefresh(current: anchor, followsToday: followsToday, now: Date())
    }
  }

  /// The period pill's menu: the basis, then the recent periods on that basis
  /// (12 months or 3 financial years, from `ReportsPeriod.recentAnchors`).
  private var periodPill: some View {
    NomiPeriodPill(title: ReportsPeriod.label(for: period), style: .onGround) {
      Picker("Period basis", selection: $basis) {
        Text("Calendar month").tag(PeriodBasis.calendarMonth)
        Text("Financial year").tag(PeriodBasis.financialYear)
      }
      Divider()
      ForEach(ReportsPeriod.recentAnchors(basis: basis, now: Date()), id: \.self) { candidate in
        Button(ReportsPeriod.label(for: ReportsPeriod.period(basis: basis, anchor: candidate))) {
          anchor = candidate
          followsToday = PeriodAnchorPolicy.followsToday(afterPicking: candidate, basis: basis, now: Date(), calendar: .current)
        }
      }
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

  /// Spent and Received side by side, each with its figure and the change
  /// against the prior period. The figures are `NomiAmountText`, one accessibility
  /// element each. The change line says so when there is no prior period.
  private func summaryCard(_ model: ReportsViewModel) -> some View {
    HStack(alignment: .top, spacing: NomiSpacing.sm) {
      summaryFigure(label: "Spent", minor: model.debitMinor, change: model.debitChangeCopy)
      Rectangle()
        .fill(NomiColor.secondaryFill)
        .frame(width: 1)
      summaryFigure(label: "Received", minor: model.creditMinor, change: model.creditChangeCopy)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 116, alignment: .topLeading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  private func summaryFigure(label: String, minor: Int, change: String?) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(label)
        .nomiTextStyle(.subhead)
        .foregroundStyle(NomiColor.inkSecondary)
      NomiAmountText(minor: minor, style: .summaryValue)
      Text(change ?? "No prior period to compare")
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  /// Daily bars on the calendar basis; monthly bars on the financial-year basis,
  /// or a load-failed card when the trend did not load.
  @ViewBuilder
  private func barsCard(_ model: ReportsViewModel) -> some View {
    if let daily = model.dailyDebitMinor {
      let highlight = ReportsSpendSeries.highlightIndex(
        count: daily.count,
        todayIndex: ReportsSpendSeries.todayIndex(period: period, now: Date())
      )
      ReportsTrendCard(
        title: "Daily spend",
        values: daily,
        highlightIndex: highlight,
        startLabel: "1",
        endLabel: "\(daily.count)",
        spokenValue: ReportsSpendSeries.peakDescription(values: daily) { "on day \($0 + 1)" }
      )
    } else if let monthlyTrend {
      switch monthlyTrend {
      case .loaded(let buckets):
        let values = buckets.map(\.debitMinor)
        ReportsTrendCard(
          title: "Monthly spend",
          values: values,
          highlightIndex: ReportsSpendSeries.highlightIndex(count: values.count, todayIndex: nil),
          startLabel: buckets.first.map { shortMonth($0.id) } ?? "",
          endLabel: buckets.last.map { shortMonth($0.id) } ?? "",
          spokenValue: ReportsSpendSeries.peakDescription(values: values) { "in \(monthName(buckets[$0].id))" }
        )
      case .failed:
        NomiLoadFailedCard(message: "Monthly spend didn’t load.") {
          retryToken += 1
        }
      }
    }
  }

  private func shortMonth(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(Locale(identifier: "en_IN")))
  }

  private func monthName(_ date: Date) -> String {
    date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "en_IN")))
  }

  /// One control, two actions. Each tap writes a fresh CSV and opens the share
  /// sheet for it at once (R12b, Y1).
  private var exportRow: some View {
    Menu {
      Button("This period") {
        share(period)
      }
      Button("All time") {
        share(.allTime)
      }
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text("Export")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
        Spacer(minLength: NomiSpacing.xs)
        Text("This period")
          .nomiTextStyle(.subhead)
          .foregroundStyle(NomiColor.inkSecondary)
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
    .accessibilityLabel("Export")
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
      let url = try ReportsCSVExport.write(transactions, names: names, periodLabel: ReportsPeriod.label(for: exportPeriod))
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
