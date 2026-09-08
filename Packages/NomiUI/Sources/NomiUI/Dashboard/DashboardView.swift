import NomiCore
import NomiPreview
import SwiftUI

/// Small, testable wiring rules that would otherwise be buried inside
/// `DashboardView.body` where XCTest cannot reach them. Kept together so the
/// AC-mandated behaviour (archived exclusion, budget-module absence) reads as
/// a policy, not an accident of how the view happens to be written.
enum DashboardWiring {
  /// The accounts card never sees archived accounts — done-when: "Archived
  /// accounts are excluded from the accounts card."
  static let accountsIncludeArchived = false

  /// Done-when: "a preview with zero budgets renders NO budget module at
  /// all... an absent view and not a hidden one." `DashboardView` acts on
  /// this with `if DashboardWiring.shouldShowBudgetModule(...)`, never
  /// `.hidden()` or `.opacity(0)`, so a `false` here means the module is
  /// never constructed.
  static func shouldShowBudgetModule(_ items: [BudgetProgress]) -> Bool {
    !items.isEmpty
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

/// The home screen (U9). Composes the period selector and every dashboard
/// card, reading exclusively through `InsightsStore` and
/// `MailConnectionService` — never `NomiIngest`, which `NomiUI` cannot import
/// at all (enforced by the package graph, not by discipline).
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

  @State private var basis: PeriodBasis = .calendarMonth
  @State private var anchor: Date = Date()
  @State private var mailState: MailConnectionState = .disconnected

  /// Bumped by every "tap to retry" — a stored property changing is what
  /// makes SwiftUI re-invoke `body` (and so re-run the `Load`-returning
  /// computed properties below) even though none of them read it, same
  /// mechanism `refreshToken` above already relies on.
  @State private var retryToken = 0

  public init(
    insightsStore: InsightsStore,
    mailConnectionService: MailConnectionService? = nil,
    recurringStore: RecurringInsightsStore? = nil,
    refreshToken: Int = 0,
    onOpenReviewQueue: (() -> Void)? = nil,
    basis: PeriodBasis = .calendarMonth,
    anchor: Date = Date()
  ) {
    self.insightsStore = insightsStore
    self.mailConnectionService = mailConnectionService
    self.recurringStore = recurringStore
    self.refreshToken = refreshToken
    self.onOpenReviewQueue = onOpenReviewQueue
    _basis = State(initialValue: basis)
    _anchor = State(initialValue: anchor)
  }

  private var period: InsightPeriod {
    DashboardPeriod.period(basis: basis, anchor: anchor)
  }

  private var insights: DashboardWiring.Load<PeriodInsights> {
    DashboardWiring.insights(for: period, from: insightsStore)
  }

  private var accounts: DashboardWiring.Load<[AccountSummary]> {
    DashboardWiring.accounts(from: insightsStore)
  }

  private var budgetProgress: DashboardWiring.Load<[BudgetProgress]>? {
    DashboardWiring.budgetProgress(
      month: DashboardWiring.budgetMonth(basis: basis, anchor: anchor, calendar: .current),
      from: insightsStore
    )
  }

  private var recentTransactions: DashboardWiring.Load<[NomiCore.Transaction]> {
    DashboardWiring.recentTransactions(from: insightsStore)
  }

  /// `nil` when there is no `recurringStore` at all — distinct from
  /// `DashboardWiring.Load`'s own two cases, same shape `budgetProgress`
  /// already uses for its own third, store-independent "nothing to show"
  /// state.
  private var recurringSeries: DashboardWiring.Load<[RecurringSeries]>? {
    guard let recurringStore else { return nil }
    return DashboardWiring.recurringSeries(from: recurringStore)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardToCard) {
        SyncStatusRow(state: mailState)
        periodSelector
        switch insights {
        case .loaded(let insights):
          HeroTotalCard(insights: insights)
          SpendPerDayChartCard(byDay: insights.byDay)
          CategoryBreakdownCard(slices: insights.byCategory)
          budgetModule
          recentTransactionsModule
          TopMerchantsCard(merchants: insights.topMerchants)
          NeedsYouCard(
            needsReviewCount: insights.needsReviewCount, uncategorizedCount: insights.uncategorizedCount,
            onTap: onOpenReviewQueue
          )
        case .failed:
          FailedLoadCaption { retryToken += 1 }
        }
        upcomingModule
        accountsModule
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
    .task {
      guard let mailConnectionService else { return }
      for await state in mailConnectionService.state {
        mailState = state
      }
    }
  }

  @ViewBuilder
  private var budgetModule: some View {
    switch budgetProgress {
    case .loaded(let items) where DashboardWiring.shouldShowBudgetModule(items):
      BudgetProgressCard(items: items)
    case .loaded:
      EmptyView()
    case .failed:
      FailedLoadCaption { retryToken += 1 }
    case nil:
      // FY basis: budgets are monthly, so there is nothing to show progress
      // against — a caption, not a hidden module masquerading as "on time".
      Text("Budgets are monthly — switch to Calendar Month to see progress.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  @ViewBuilder
  private var recentTransactionsModule: some View {
    switch recentTransactions {
    case .loaded(let transactions):
      RecentTransactionsCard(transactions: transactions)
    case .failed:
      FailedLoadCaption { retryToken += 1 }
    }
  }

  /// `nil` renders `EmptyView()` — the card is absent, not hidden — the same
  /// three-way shape `budgetModule` already handles for its own `nil` case.
  @ViewBuilder
  private var upcomingModule: some View {
    switch recurringSeries {
    case .loaded(let series):
      UpcomingCard(series: series)
    case .failed:
      FailedLoadCaption { retryToken += 1 }
    case nil:
      EmptyView()
    }
  }

  @ViewBuilder
  private var accountsModule: some View {
    switch accounts {
    case .loaded(let accounts):
      AccountsCard(accounts: accounts)
    case .failed:
      FailedLoadCaption { retryToken += 1 }
    }
  }

  private var periodSelector: some View {
    HStack(spacing: NomiSpacing.sm) {
      Button {
        anchor = DashboardPeriod.shiftedAnchor(anchor, basis: basis, by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .foregroundStyle(NomiColor.textSecondary)
      }
      Text(DashboardPeriod.label(for: period))
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        anchor = DashboardPeriod.shiftedAnchor(anchor, basis: basis, by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.textSecondary)
      }
      NomiSegmentedPill(basis: $basis)
    }
  }
}

/// F3: a "Couldn't load" state, distinct from an empty one — tapping it
/// bumps `retryToken`, which is all a retry can do here since none of these
/// reads carry their own retry mechanism; the next `body` re-evaluation
/// simply tries the read again.
private struct FailedLoadCaption: View {
  let retry: () -> Void

  var body: some View {
    Button(action: retry) {
      Text("Couldn't load — tap to retry")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.overBudget)
    }
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

#Preview("Dashboard — default, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — accessibility 3, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}

/// M9 done-when: "counts > 0 with a chevron" at the dashboard level — proves
/// `onOpenReviewQueue` actually reaches `NeedsYouCard`, not just that card's
/// own preview in isolation.
#Preview("Dashboard — needs-you card tappable, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
      onOpenReviewQueue: {}
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — thin state, under 10 transactions, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FakeInsightsStore(transactions: Array(PreviewData.transactions.prefix(6)), budgets: []),
      mailConnectionService: FakeMailConnectionService()
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — zero budgets, module absent, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(budgets: []), mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — financial year basis, budget caption, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
      basis: .financialYear
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — failed load, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FailingInsightsStorePreviewFixture(), mailConnectionService: FakeMailConnectionService()
    )
  }
  .preferredColorScheme(.dark)
}

/// U17b done-when: a `recurringStore` renders the Upcoming card — proves the
/// wiring, not just `UpcomingCard`'s own previews, which never touch
/// `DashboardView.recurringSeries` or `upcomingModule` at all.
#Preview("Dashboard — upcoming card populated, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService(),
      recurringStore: FakeRecurringStore()
    )
  }
  .preferredColorScheme(.dark)
}

/// U17b done-when: `recurringStore: nil` (the default every other preview in
/// this file already uses) renders no Upcoming card at all — an absent view,
/// same rule as the zero-budgets preview above, named explicitly rather than
/// left as an unlabelled side effect of every other preview's default.
#Preview("Dashboard — no recurring store, upcoming card absent, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
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
