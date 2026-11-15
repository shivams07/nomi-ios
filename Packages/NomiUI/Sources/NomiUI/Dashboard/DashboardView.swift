import NomiCore
import NomiPreview
import SwiftUI

/// The two destinations Home's own cards link to. The screens themselves
/// (`BudgetsScreen`, `SubscriptionsScreen`) and the `navigationDestination`
/// that resolves this route are `ui-root-wiring`'s (M6) job — until that
/// merges, `NavigationLink(value:)` sites built from this render disabled on
/// device, which is why every preview below wraps in a `NavigationStack`.
public enum DashboardRoute: Hashable, Sendable {
  case budgets
  case subscriptions
}

/// Small, testable wiring rules that would otherwise be buried inside
/// `DashboardView.body` where XCTest cannot reach them. Kept together so the
/// AC-mandated behaviour (archived exclusion, budget-module state) reads as
/// a policy, not an accident of how the view happens to be written.
enum DashboardWiring {
  /// The accounts card never sees archived accounts — done-when: "Archived
  /// accounts are excluded from the accounts card."
  static let accountsIncludeArchived = false

  /// v5 (`nomi-ui-refresh`): the empty-budgets case is a visible prompt card
  /// now, not a hidden module — `budgetModule(_:)` replaces the old
  /// `shouldShowBudgetModule` boolean gate with the two states
  /// `RemainingBudgetCard` actually renders.
  enum BudgetModuleState: Equatable {
    case prompt
    case remaining(BudgetTotals.Totals)
  }

  static func budgetModule(_ items: [BudgetProgress]) -> BudgetModuleState {
    guard let totals = BudgetTotals.compute(items) else { return .prompt }
    return .remaining(totals)
  }

  /// `RecentTransactionsCard` shows five rows and trims to five itself; the
  /// dashboard used to hand it `transactions(in: .allTime)`, so every write
  /// materialised the whole ledger to render those five (F2). This is here
  /// rather than inline in `body` so a test can hold it to that - `body`
  /// itself is not reachable from `swift test`.
  static let recentTransactionLimit = 5

  /// A read that failed is not a read that succeeded and found nothing (F3).
  /// `try?` used to conflate the two — a store error rendered identically to
  /// a genuinely empty period. `.failed` is a distinct, retryable state;
  /// `.loaded`, even with an empty payload, renders the same card it always
  /// did.
  enum Load<T> {
    case loaded(T)
    case failed
  }

  @MainActor
  static func recentTransactions(from store: InsightsStore) -> Load<[NomiCore.Transaction]> {
    do {
      return .loaded(try store.recentTransactions(limit: recentTransactionLimit))
    } catch {
      return .failed
    }
  }

  /// `nil` in financial-year basis: budgets are monthly and the FY view has
  /// no single calendar month to evaluate progress against.
  static func budgetMonth(basis: PeriodBasis, anchor: Date, calendar: Calendar) -> (year: Int, month: Int)? {
    guard basis == .calendarMonth else { return nil }
    let components = calendar.dateComponents([.year, .month], from: anchor)
    guard let year = components.year, let month = components.month else { return nil }
    return (year, month)
  }

  /// M9: `NeedsYouCard` is tappable exactly when it has something to show —
  /// the same condition its own `isCaughtUp` uses, mirrored here as a pure
  /// rule so a test can hold it without going through the view.
  static func needsYouIsTappable(needsReviewCount: Int, uncategorizedCount: Int) -> Bool {
    needsReviewCount > 0 || uncategorizedCount > 0
  }

  /// G1: which list the Needs-you card's tap opens. Review leads, as
  /// `NeedsYouText.line` does, because the Needs review chip filters on
  /// `needsReview` and is empty for an uncategorized-only card.
  enum NeedsYouDestination: Equatable {
    case reviewQueue
    case uncategorized
  }

  static func needsYouDestination(needsReviewCount: Int, uncategorizedCount: Int) -> NeedsYouDestination? {
    if needsReviewCount > 0 { return .reviewQueue }
    if uncategorizedCount > 0 { return .uncategorized }
    return nil
  }

  /// The handler the card's tap runs for these counts, or nil when it has
  /// none. Generic so a test can hold the choice between the two handlers with
  /// sentinel values, which is the routing decision itself.
  static func needsYouHandler<Handler>(
    needsReviewCount: Int,
    uncategorizedCount: Int,
    reviewQueue: Handler?,
    uncategorized: Handler?
  ) -> Handler? {
    switch needsYouDestination(needsReviewCount: needsReviewCount, uncategorizedCount: uncategorizedCount) {
    case .reviewQueue:
      return reviewQueue
    case .uncategorized:
      return uncategorized
    case nil:
      return nil
    }
  }

  // MARK: - D26: the Needs-you review count is the Ledger chip's count

  /// The Ledger's Needs review chip counts every flagged row, whatever the
  /// period. Home's card read the selected period, so the two disagreed in any
  /// month but the one that held them all. This read is the chip's count, as
  /// its own `Load` so a failure is not taken for zero (F3).
  @MainActor
  static func needsReviewAllTime(from store: InsightsStore) -> Load<Int> {
    do {
      return .loaded(try store.needsReviewCountAllTime())
    } catch {
      return .failed
    }
  }

  /// The counts the Needs-you card shows. The review count is the all-time one,
  /// and the uncategorized count is still the selected period's, as before.
  struct NeedsYouInputs: Equatable {
    let needsReviewCount: Int
    let uncategorizedCount: Int
  }

  /// Takes the review count from `needsReviewAllTime`, never from
  /// `period.needsReviewCount`, which is the selected period's. Pure, so a test
  /// can hold that choice without the view.
  static func needsYouInputs(period: PeriodInsights, needsReviewAllTime: Int) -> NeedsYouInputs {
    NeedsYouInputs(
      needsReviewCount: needsReviewAllTime,
      uncategorizedCount: period.uncategorizedCount
    )
  }

  // MARK: - F3: the rest of the dashboard's reads, pulled out of `body` for
  // the same reason `recentTransactions(from:)` above already is — `swift
  // test` cannot reach `DashboardView.body` or its private computed
  // properties at all.

  @MainActor
  static func insights(for period: InsightPeriod, from store: InsightsStore) -> Load<PeriodInsights> {
    do {
      return .loaded(try store.insights(for: period))
    } catch {
      return .failed
    }
  }

  /// HM1 no longer draws the Accounts card on Home (it was cut from the
  /// approved Main artboard). The read and its rule stay here, unchanged, so
  /// every existing member of `DashboardWiring` is still in place.
  @MainActor
  static func accounts(from store: InsightsStore) -> Load<[AccountSummary]> {
    do {
      return .loaded(try store.accountSummaries(includeArchived: accountsIncludeArchived))
    } catch {
      return .failed
    }
  }

  /// U17b. Unlike `accounts`/`recentTransactions`, there is no third "no
  /// store at all" case to represent here — that lives one level up, in
  /// `DashboardView.recurringSeries`, as the `nil` around this `Load` rather
  /// than a case inside it. This only ever runs once a store exists.
  @MainActor
  static func recurringSeries(from store: RecurringInsightsStore) -> Load<[RecurringSeries]> {
    do {
      return .loaded(try store.recurringSeries())
    } catch {
      return .failed
    }
  }

  /// `month == nil` (FY basis) passes straight through as `nil` — a third
  /// state, distinct from both cases of `Load`, since the FY basis has no
  /// budget concept at all rather than a successful empty answer or a
  /// failure.
  @MainActor
  static func budgetProgress(month: (year: Int, month: Int)?, from store: InsightsStore) -> Load<[BudgetProgress]>? {
    guard let month else { return nil }
    do {
      return .loaded(try store.budgetProgress(year: month.year, month: month.month))
    } catch {
      return .failed
    }
  }
}

/// The `.task(id:)` identity for Home's load (S1a). A change of period, of the
/// cache generation or of the retry token reloads every module, once.
private struct HomeLoadKey: Hashable {
  let period: InsightPeriod
  let refreshToken: Int
  let retryToken: Int
}

/// The home screen (U9; v5 `nomi-ui-refresh` §Home, M2; HM1 `home-hero`).
/// The approved Main artboard: a gradient hero with the period pill and
/// Settings gear, the spent figure, one delta chip and the sparkline, over a
/// flat sheet with the Needs-you card, remaining budget, Recent and Upcoming.
/// Reads only through `InsightsStore` and `MailConnectionService` — never
/// `NomiIngest`, which `NomiUI` cannot import at all (enforced by the package
/// graph, not by discipline).
public struct DashboardView: View {
  public let insightsStore: InsightsStore
  public let mailConnectionService: MailConnectionService?

  /// U17b. `nil` — the default, so every existing preview/test call site
  /// keeps compiling — means the card is absent, same rule as the budget
  /// module's zero-items case: never constructed, not hidden.
  public let recurringStore: RecurringInsightsStore?

  /// Never read. `InsightsCache` lives in `NomiApp`, which `NomiUI` cannot
  /// depend on, so the composition root republishes its generation as this
  /// plain `Int` and passes a new value in on every write. SwiftUI
  /// re-invokes `body` when a stored property of a view value changes
  /// regardless of whether `body` reads it — that's what makes this work,
  /// not a coincidence of it being unused. Do not delete it for looking dead.
  public let refreshToken: Int

  /// M9. `nil` — the default, so every existing preview/test call site keeps
  /// compiling — leaves `NeedsYouCard` non-interactive, same "absent
  /// affordance, not a disabled one" rule the rest of this file already
  /// applies to modules. `root-banner-and-review-route` is what actually
  /// supplies this from `RootView`.
  public let onOpenReviewQueue: (() -> Void)?

  /// G1. Opens the Ledger's Uncategorized chip. The Needs-you card calls it
  /// when its only count is uncategorized rows (review count zero), because
  /// the Needs review chip is empty in that state. `nil` leaves the card
  /// non-interactive in that state, as `onOpenReviewQueue` does.
  public let onOpenUncategorized: (() -> Void)?

  /// v5 (`nomi-ui-refresh`, M2). `nil` — same default-so-every-call-site-
  /// compiles rule as `onOpenReviewQueue` — leaves `RecentTransactionsCard`'s
  /// rows non-interactive. `ui-root-wiring` (M6) supplies this, opening the
  /// transaction sheet.
  public let onSelectTransaction: ((UUID) -> Void)?

  @State private var basis: PeriodBasis = .calendarMonth
  @State private var anchor: Date = Date()
  /// `true` until the user picks a period, and again when a picked period
  /// contains today. Decides whether a refresh moves `anchor` to now (R12b, Y1).
  @State private var followsToday = true
  @State private var mailState: MailConnectionState = .disconnected

  /// Bumped by every "tap to retry". It is part of `HomeLoadKey`, so the bump
  /// re-runs the load in `.task(id:)`, which is the only read path (S1a).
  @State private var retryToken = 0

  /// Every read the screen shows, loaded by `.task(id:)` (S1a). Built once with
  /// the view's stores; the stores are the app's own and do not change for the
  /// life of the Home tab.
  @State private var model: HomeModel

  /// The "Add a transaction" action (F3). `nil` until RootView sets it, and
  /// the second first-run card's button is hidden while it is nil.
  @Environment(\.nomiAddTransaction) private var addTransaction

  /// The "show the Ledger" action (FU-1). `nil` until RootView sets it, and the
  /// Recent header's "See all" is hidden while it is nil.
  @Environment(\.nomiShowLedger) private var showLedger

  public init(
    insightsStore: InsightsStore,
    mailConnectionService: MailConnectionService? = nil,
    recurringStore: RecurringInsightsStore? = nil,
    refreshToken: Int = 0,
    onOpenReviewQueue: (() -> Void)? = nil,
    onOpenUncategorized: (() -> Void)? = nil,
    onSelectTransaction: ((UUID) -> Void)? = nil,
    basis: PeriodBasis = .calendarMonth,
    anchor: Date = Date()
  ) {
    self.insightsStore = insightsStore
    self.mailConnectionService = mailConnectionService
    self.recurringStore = recurringStore
    self.refreshToken = refreshToken
    self.onOpenReviewQueue = onOpenReviewQueue
    self.onOpenUncategorized = onOpenUncategorized
    self.onSelectTransaction = onSelectTransaction
    _basis = State(initialValue: basis)
    _anchor = State(initialValue: anchor)
    _model = State(initialValue: HomeModel(insightsStore: insightsStore, recurringStore: recurringStore))
  }

  private var period: InsightPeriod {
    DashboardPeriod.period(basis: basis, anchor: anchor)
  }

  /// D14. Read through the service on each render: `MailStack.history` reads the
  /// preferences every time, so a connect that completes is seen on the next
  /// render. No service means no connection has ever been made here.
  private var mailHistory: MailConnectionHistory {
    mailConnectionService?.history ?? .never
  }

  /// A failed read is not evidence that there are no transactions, so only a
  /// successful empty read counts as "none" and can show first run.
  private func hasAnyTransaction(_ transactions: DashboardWiring.Load<[NomiCore.Transaction]>) -> Bool {
    switch transactions {
    case .loaded(let rows):
      return !rows.isEmpty
    case .failed:
      return true
    }
  }

  /// The body reads only `model`. Every store read happens in `model.load`, once
  /// per `HomeLoadKey`, from the `.task(id:)` below (S1a).
  public var body: some View {
    NomiHeroScaffold(heroBottomSpacing: 12) {
      navRow
    } hero: {
      heroContent
    } sheet: {
      sheetContent
    }
    .task {
      guard let mailConnectionService else { return }
      for await state in mailConnectionService.state {
        mailState = state
      }
    }
    .task(id: HomeLoadKey(period: period, refreshToken: refreshToken, retryToken: retryToken)) {
      model.load(period: period)
    }
    .onChange(of: refreshToken) { _, _ in
      anchor = PeriodAnchorPolicy.anchorAfterRefresh(current: anchor, followsToday: followsToday, now: Date())
    }
  }

  /// The sheet in its state. Nothing is drawn until the transactions, the period
  /// and the review count have loaded, since the first-run rule needs the first.
  @ViewBuilder
  private var sheetContent: some View {
    if let transactions = model.recentTransactions,
       let insights = model.insights,
       let needsReview = model.needsReview {
      switch HomeLayout.mode(mail: mailState, hasAnyTransaction: hasAnyTransaction(transactions)) {
      case .firstRun:
        firstRunCards
      case .normal(let showAttention):
        homeSheet(
          showAttention: showAttention,
          insights: insights,
          needsReview: needsReview,
          transactions: transactions
        )
      }
    }
  }

  // MARK: - Hero

  /// The nav row (HM1, S1a): the period pill on the left, and on the right a
  /// search circle and the Settings circle, both 44 pt heroControl glass and 8 pt
  /// apart. The pill's menu holds the basis picker and the recent periods. The
  /// search circle opens Activity with its search field (I-15); it is hidden
  /// while no root has wired `\.nomiShowLedger`.
  private var navRow: some View {
    HStack(spacing: 0) {
      NomiPeriodPill(title: DashboardPeriod.label(for: period), style: .onHero) {
        periodMenu
      }
      Spacer(minLength: 12)
      HStack(spacing: 8) {
        if NomiShowLedgerLogic.showsControl(isWired: showLedger != nil), let showLedger {
          Button {
            showLedger(.search(""))
          } label: {
            NomiHeroIcon(systemName: "magnifyingglass")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Search")
        }
        NavigationLink(value: HomeRoute.settings) {
          NomiHeroIcon(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
      }
    }
  }

  @ViewBuilder
  private var periodMenu: some View {
    Picker("Period basis", selection: $basis) {
      Text("Calendar month").tag(PeriodBasis.calendarMonth)
      Text("Financial year").tag(PeriodBasis.financialYear)
    }
    Divider()
    ForEach(DashboardPeriod.recentAnchors(basis: basis, now: Date()), id: \.self) { candidate in
      Button(DashboardPeriod.label(for: DashboardPeriod.period(basis: basis, anchor: candidate))) {
        anchor = candidate
        followsToday = PeriodAnchorPolicy.followsToday(afterPicking: candidate, basis: basis, now: Date(), calendar: .current)
      }
    }
  }

  /// The hero's Spent or Income control writes the model's kind. Switching it
  /// reads nothing.
  private var heroContent: some View {
    HeroTotalCard(figures: heroFigures, period: period, kind: $model.kind)
  }

  /// A loading hero is not a zero, and a failed one is not a loaded one. Each
  /// is its own figure state.
  private var heroFigures: HeroTotalCard.Figures {
    switch model.insights {
    case .loaded(let insights)?:
      return .loaded(insights)
    case .failed?:
      return .unavailable
    case nil:
      return .loading
    }
  }

  // MARK: - Sheet

  /// The Home sheet in its normal state, in artboard order: the sync banner
  /// (only when mail needs attention), Needs you, Remaining budget, Recent and
  /// Upcoming. Every module is its own read, so each failure is its own card
  /// with its own retry.
  private func homeSheet(
    showAttention: Bool,
    insights: DashboardWiring.Load<PeriodInsights>,
    needsReview: DashboardWiring.Load<Int>,
    transactions: DashboardWiring.Load<[NomiCore.Transaction]>
  ) -> some View {
    let categories: [CategoryBadge]
    if case .loaded(let loaded) = insights {
      categories = loaded.categories
    } else {
      categories = []
    }
    return VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
      if showAttention {
        syncBanner
      }
      needsYouModule(insights, needsReview: needsReview)
      budgetModule
      recentModule(transactions, categories: categories)
      upcomingModule
    }
  }

  /// The mail banner, shown only while mail is disconnected or failed. Tapping
  /// it opens Connect mail.
  private var syncBanner: some View {
    NavigationLink(value: HomeRoute.connectMail) {
      SyncStatusRow(state: mailState, history: mailHistory)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func needsYouModule(
    _ result: DashboardWiring.Load<PeriodInsights>,
    needsReview: DashboardWiring.Load<Int>
  ) -> some View {
    if let inputs = needsYouInputs(result, needsReview: needsReview) {
      NeedsYouCard(
        needsReviewCount: inputs.needsReviewCount,
        uncategorizedCount: inputs.uncategorizedCount,
        onTap: needsYouTap(for: inputs)
      )
    } else {
      // The Needs-you counts come from the period read and the review read. A
      // failure in either is not a zero, so without a card here a failed read
      // would leave no retry on screen.
      NomiLoadFailedCard(message: "Spending didn’t load.") { retryToken += 1 }
    }
  }

  /// The card's counts when both reads loaded, otherwise `nil`. D26 takes the
  /// review count from the all-time read and the rest from the period.
  private func needsYouInputs(
    _ result: DashboardWiring.Load<PeriodInsights>,
    needsReview: DashboardWiring.Load<Int>
  ) -> DashboardWiring.NeedsYouInputs? {
    guard case .loaded(let insights) = result, case .loaded(let reviewAllTime) = needsReview else {
      return nil
    }
    return DashboardWiring.needsYouInputs(period: insights, needsReviewAllTime: reviewAllTime)
  }

  /// The Needs-you tap for these counts (G1): review opens the review queue,
  /// uncategorized-only opens the Uncategorized chip, and a card with nothing
  /// to show has no tap.
  private func needsYouTap(for inputs: DashboardWiring.NeedsYouInputs) -> (() -> Void)? {
    DashboardWiring.needsYouHandler(
      needsReviewCount: inputs.needsReviewCount,
      uncategorizedCount: inputs.uncategorizedCount,
      reviewQueue: onOpenReviewQueue,
      uncategorized: onOpenUncategorized
    )
  }

  @ViewBuilder
  private var budgetModule: some View {
    switch model.budgets {
    case .monthly(.loaded(let items))?:
      NavigationLink(value: DashboardRoute.budgets) {
        RemainingBudgetCard(state: DashboardWiring.budgetModule(items), referenceDate: anchor)
      }
      .buttonStyle(.plain)
    case .monthly(.failed)?:
      NomiLoadFailedCard(message: "Budgets didn’t load.") { retryToken += 1 }
    case .notMonthly?:
      // FY basis: budgets are monthly, so there is nothing to show progress
      // against — a caption, not a hidden module masquerading as "on time".
      Text("Budgets are monthly — switch to Calendar Month to see progress.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    case nil:
      // Not loaded yet: the module is drawn once its read has finished.
      EmptyView()
    }
  }

  /// The Recent header (Main artboard, 602 to 646). "See all" opens the Ledger
  /// tab. It is drawn only while RootView has wired `\.nomiShowLedger`. The
  /// caption keeps the artboard's 14 pt medium navy text, and its hit area is
  /// at least 44 by 44 pt.
  private var recentHeader: some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      Text("Recent")
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NomiSpacing.xs)
      if NomiShowLedgerLogic.showsControl(isWired: showLedger != nil), let showLedger {
        Button {
          showLedger()
        } label: {
          Text("See all")
            .nomiTextStyle(.chip)
            .foregroundStyle(NomiColor.navy)
            .frame(minWidth: NomiSpacing.minTarget, minHeight: NomiSpacing.minTarget, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all recent transactions")
      }
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
  }

  @ViewBuilder
  private func recentModule(
    _ result: DashboardWiring.Load<[NomiCore.Transaction]>,
    categories: [CategoryBadge]
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      recentHeader
      switch result {
      case .loaded(let transactions):
        RecentTransactionsCard(
          transactions: transactions,
          badges: RecentBadges.lookup(categories),
          onSelect: onSelectTransaction
        )
      case .failed:
        NomiLoadFailedCard(message: "Recent transactions didn’t load.") { retryToken += 1 }
      }
    }
  }

  /// `nil` renders `EmptyView()` — the card is absent, not hidden — the same
  /// three-way shape `budgetModule` already handles for its own `nil` case.
  @ViewBuilder
  private var upcomingModule: some View {
    switch model.upcoming {
    case .loaded(.loaded(let series))?:
      NavigationLink(value: DashboardRoute.subscriptions) {
        UpcomingCard(series: series)
      }
      .buttonStyle(.plain)
    case .loaded(.failed)?:
      NomiLoadFailedCard(message: "Upcoming didn’t load.") { retryToken += 1 }
    case .absent?, nil:
      EmptyView()
    }
  }

  // MARK: - First run

  /// The first-run sheet (HomeFirstRun artboard): Connect mail is the primary
  /// card and Add a transaction the secondary. The Add button is hidden while
  /// no add action is in the environment.
  private var firstRunCards: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
      connectMailCard
      addTransactionCard
    }
  }

  private var connectMailCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "envelope")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .foregroundStyle(NomiColor.iconGlyph)
          .frame(width: 40, height: 40)
          .background(Circle().fill(NomiColor.iconTile))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Connect your mail")
            .nomiTextStyle(.headline)
            .foregroundStyle(NomiColor.ink)
          Text("Nomi reads bank and card alerts in your mail to log spending.")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkDeep)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      NavigationLink(value: HomeRoute.connectMail) {
        Text("Connect mail")
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 52))
    }
    .nomiCard(padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
  }

  private var addTransactionCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Add a transaction")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Text("Log cash or a payment by hand.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      if let addTransaction {
        Button {
          addTransaction()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus")
              .resizable()
              .scaledToFit()
              .frame(width: 18, height: 18)
              .accessibilityHidden(true)
            Text("Add transaction")
          }
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.navy)
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
          .background(Capsule().fill(NomiColor.card))
          .overlay {
            Capsule().strokeBorder(NomiColor.inkDeep.opacity(0.14), lineWidth: 1)
          }
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
      }
    }
    .nomiCard(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
  }
}

/// Manual conformance because `InsightsStore`/`MailConnectionService` are
/// `AnyObject` protocols, not `Equatable` ones — identity stands in for
/// value equality on those two. Exists so a test can assert that two
/// otherwise-identical view values differing only in `refreshToken` compare
/// as different.
extension DashboardView: Equatable {
  public static func == (lhs: DashboardView, rhs: DashboardView) -> Bool {
    lhs.insightsStore === rhs.insightsStore
      && lhs.mailConnectionService === rhs.mailConnectionService
      && lhs.recurringStore === rhs.recurringStore
      && lhs.refreshToken == rhs.refreshToken
  }
}

#Preview("Dashboard · default") {
  NavigationStack {
    NomiTabShell {
      DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · accessibility 3") {
  NavigationStack {
    NomiTabShell {
      DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
    }
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}

#Preview("Dashboard · first run") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FakeInsightsStore(transactions: [], budgets: []),
        mailConnectionService: FakeMailConnectionService()
      )
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · needs-you card tappable") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
        onOpenReviewQueue: {}
      )
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · thin state, under 10 transactions") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FakeInsightsStore(transactions: Array(PreviewData.transactions.prefix(6)), budgets: []),
        mailConnectionService: FakeMailConnectionService()
      )
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · zero budgets, prompt card") {
  NavigationStack {
    NomiTabShell {
      DashboardView(insightsStore: FakeInsightsStore(budgets: []), mailConnectionService: FakeMailConnectionService())
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · financial year basis, budget caption") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
        basis: .financialYear
      )
    }
  }
  .preferredColorScheme(.light)
}

#Preview("Dashboard · failed load") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FailingInsightsStorePreviewFixture(), mailConnectionService: FakeMailConnectionService()
      )
    }
  }
  .preferredColorScheme(.light)
}

/// U17b done-when: a `recurringStore` renders the Upcoming card — proves the
/// wiring, not just `UpcomingCard`'s own previews, which never touch
/// `DashboardView.recurringSeries` or `upcomingModule` at all.
#Preview("Dashboard · upcoming card populated") {
  NavigationStack {
    NomiTabShell {
      DashboardView(
        insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
        recurringStore: FakeRecurringStore()
      )
    }
  }
  .preferredColorScheme(.light)
}

/// U17b done-when: `recurringStore: nil` (the default every other preview in
/// this file already uses) renders no Upcoming card at all — an absent view,
/// same rule as the zero-budgets preview above, named explicitly rather than
/// left as an unlabelled side effect of every other preview's default.
#Preview("Dashboard · no recurring store, upcoming card absent") {
  NavigationStack {
    NomiTabShell {
      DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
    }
  }
  .preferredColorScheme(.light)
}

/// A store that fails every read — for the preview above only. Kept local to
/// this file rather than added to `NomiPreview`, which is not in this unit's
/// file list.
@MainActor
private final class FailingInsightsStorePreviewFixture: InsightsStore {
  private struct Failure: Error {}
  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw Failure() }
  func trend(months: Int) throws -> [MonthBucket] { throw Failure() }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { throw Failure() }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { throw Failure() }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { throw Failure() }
  func recentTransactions(limit: Int) throws -> [NomiCore.Transaction] { throw Failure() }
}
