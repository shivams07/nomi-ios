import Foundation
import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The day header's text. Pulled out as a pure function, same reasoning as
/// `HeroIncomeExpense` in `HeroTotalCard.swift`: this just wraps
/// `NomiFormatters.dayMonthAdaptive`, but a test against that formatter alone
/// can't fail against an unmodified `LedgerScreen` — it doesn't reference this
/// file at all. Routing `dayHeader` through this lets `LedgerDayHeaderTests`
/// exercise the actual seam this screen calls, not just the formatter it
/// happens to wrap.
enum LedgerDayHeaderText {
  static func string(for day: Date, relativeTo referenceDate: Date) -> String {
    NomiFormatters.dayMonthAdaptive(day, relativeTo: referenceDate)
  }
}

/// Geometry from the approved Ledger artboards (LG): rows are 64 pt, day
/// headers 20 pt high before Dynamic Type grows them.
private enum LedgerMetrics {
  static let rowHeight: CGFloat = 64
  static let dayHeaderHeight: CGFloat = 20
}

/// The first-run Ledger's band: the scroll container's height less the tab bar's
/// reserved space, so the block centres between the header and the bar's top.
/// Pure, so `LedgerFirstRunBandTests` pins the arithmetic. The reserve is the
/// environment's `\.nomiTabBarReserve` (S2), which RootView measures from the bar.
enum LedgerFirstRunBand {
  static func height(containerHeight: CGFloat, tabBottomReserve: CGFloat) -> CGFloat {
    guard containerHeight.isFinite, tabBottomReserve.isFinite else { return 0 }
    return max(0, containerHeight - max(0, tabBottomReserve))
  }
}

/// The list's top marker, scrolled to after "Show <previous period>".
private enum LedgerScrollTarget {
  static let top = "ledger-top"
}

/// The Ledger screen (U14) — the transaction list the UI direction specified
/// and no unit was ever given (design §2.19(2)). A tab-root screen like
/// `DashboardView`: `NomiTabShell` supplies the tab chrome, and this screen
/// sets its own large title.
///
/// Reads categories/accounts via `@Query` directly against the `@Model` types
/// (design's read/write asymmetry — see `CategoriesScreen`) and takes
/// `transactionStore`/`categoryStore` by init like every other screen, for the
/// one write action this screen offers: dismissing a needs-review row or
/// deleting a mis-imported one, both via `contextMenu` (`.swipeActions` is
/// iOS-only and this package's `swift test` also builds for plain macOS — see
/// `AccountsScreen`). `categoryStore` has no create/rename/delete affordance
/// here — that stays `CategoriesScreen`'s job — but is accepted for the same
/// construction contract as every other screen.
///
/// **G1 (DEC-04):** the list shows one calendar month or financial year at a
/// time, chosen with the period pill. The period is `LedgerPeriod.range`, the
/// same range Home's figure for that label is computed over, so the two agree.
/// The transaction table is never read whole: `LedgerTransactionList` owns the
/// `@Query`s, one bounded by the period and one the flagged queue (see that
/// type). Search and Needs review are queues and ignore the period.
public struct LedgerScreen: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore
  public let accountStore: AccountStore
  public let editor: TransactionEditing
  public let suggester: (any CategorySuggesting)?
  /// Searches the whole ledger for a non-blank query (D2). Nil in previews and
  /// until the app passes it; the box then filters the selected period in
  /// memory, as it always did.
  public let transactionSearch: (any TransactionSearching)?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var accounts: [NomiCore.Account]

  @State private var selection: LedgerChipSelection = .all
  /// The period, as Home holds it: a basis and an anchor date inside the period.
  /// Opens on the current calendar month and is not kept across launches.
  @State private var basis: PeriodBasis = .calendarMonth
  @State private var anchor: Date = Date()
  @State private var now = Date()
  @State private var searchText = ""
  @State private var presented: PresentedTransaction?
  /// Rows from `transactionSearch` for the current query. Nil means "no
  /// whole-ledger results to show", which is the period list. A non-nil
  /// array is shown as-is, even when empty.
  @State private var searchResults: [NomiCore.Transaction]?
  /// The last whole-ledger search threw. The list falls back to the period and
  /// says so, rather than showing nothing or a silent partial answer.
  @State private var searchFailed = false
  /// Bumped to re-run the search with the same query, once the detail sheet
  /// closes or a row is changed from the list. Results read before then may
  /// point at a deleted or edited row.
  @State private var searchGeneration = 0
  /// Reported by the list: whether the period holds any row, and how many need
  /// review across the whole ledger (the chip's count).
  @State private var windowSummary = LedgerWindowSummary.unreported
  /// The bottom reserve for the Activity tab (F3b). 0 on a pushed screen.
  @Environment(\.nomiTabBarReserve) private var tabBarReserve
  /// The request the Activity stack was opened with (RootView sets it). `.search`
  /// prefills the search box once, in `onAppear`.
  @Environment(\.nomiActivityRequest) private var activityRequest
  /// Spent by the first `onAppear`, so the prefill is written once per screen instance.
  @State private var prefillGate = LedgerPrefillGate()

  /// A sheet does not inherit the root's `modelContainer` — the detail
  /// screen's own `@Query` would trap at runtime (not in CI, which never
  /// builds a container in the first place) without this.
  @Environment(\.modelContext) private var modelContext

  public init(
    transactionStore: TransactionStore,
    categoryStore: CategoryStore,
    accountStore: AccountStore,
    editor: TransactionEditing,
    initialChip: LedgerChipSelection = .all,
    suggester: (any CategorySuggesting)? = nil,
    transactionSearch: (any TransactionSearching)? = nil
  ) {
    self.transactionStore = transactionStore
    self.categoryStore = categoryStore
    self.accountStore = accountStore
    self.editor = editor
    self.suggester = suggester
    self.transactionSearch = transactionSearch
    self._selection = State(initialValue: initialChip)
  }

  /// The selected period's half-open range, from the one definition Home uses.
  private var range: Range<Date> {
    LedgerPeriod.range(basis: basis, anchor: anchor, calendar: .current, now: now)
  }

  /// The selected period's label, e.g. "November 2026" or "FY 2026–27".
  private var periodLabel: String {
    DashboardPeriod.label(for: DashboardPeriod.period(basis: basis, anchor: anchor, calendar: .current))
  }

  /// A search is active and its whole-ledger results are in hand. Until they
  /// are, the list filters the period in memory, and the period still applies.
  private var wholeLedgerSearchActive: Bool {
    LedgerSearch.normalized(searchText) != nil && searchResults != nil
  }

  /// The chip the list applies. A routed category that no longer exists falls back
  /// to All (S2), so nothing filters by an id that matches no category.
  private var activeSelection: LedgerChipSelection {
    LedgerChipRow.effective(selection, categoryNames: categoryNamesByID)
  }

  private var scope: LedgerScope {
    LedgerScope.resolve(selection: activeSelection, wholeLedgerSearchActive: wholeLedgerSearchActive)
  }

  /// The period named in copy, or nil when no period is in effect.
  private var scopedPeriodLabel: String? {
    scope == .period ? periodLabel : nil
  }

  /// U16: the chip's single-select state and the search box, folded into
  /// the one value `LedgerFilterPredicate.matches` reads. `TransactionFilter`
  /// carries a `Set` of category ids for a caller that might multi-select;
  /// this screen's chip never produces more than one.
  private var filter: TransactionFilter {
    switch activeSelection {
    case .all, .spent, .income, .transfers:
      // The kind chips are applied in memory by `LedgerFiltering.kindMatches`, so
      // the predicate carries only the search here.
      return TransactionFilter(searchText: searchText)
    case .category(let id):
      return TransactionFilter(categoryIDs: [id], searchText: searchText)
    case .uncategorized:
      return TransactionFilter(uncategorizedOnly: true, searchText: searchText)
    case .needsReview:
      return TransactionFilter(searchText: searchText, needsReviewOnly: true)
    }
  }

  /// A chip other than All is selected, or the search box holds a query.
  private var isFiltered: Bool {
    activeSelection != .all || LedgerSearch.normalized(searchText) != nil
  }

  /// Decides the empty treatment, and whether the chip row and search bar show.
  /// Only `.empty` hides them: the store has no transactions, so there is
  /// nothing to filter or search.
  private var emptyKind: LedgerEmptyKind {
    LedgerEmptyKind.of(
      hasRows: windowSummary.hasRows, storeHasRows: windowSummary.storeHasRows, isFiltered: isFiltered)
  }

  /// SwiftData fixes a `@Query`'s predicate at the view instance's
  /// construction (see `.id(queryKey)`'s note, below). Only the period is baked
  /// into that predicate — the chip and search box are read back out of plain
  /// `filter` state in `LedgerTransactionList.rows` — so changing the period is
  /// the only thing that needs a new instance; typing a search character or
  /// switching a chip must not rebuild the list, or it re-runs the `@Query`
  /// fetch and drops `pendingDeleteID`/`errorMessage` on every keystroke.
  private struct QueryKey: Hashable {
    let range: Range<Date>
  }

  private var queryKey: QueryKey {
    QueryKey(range: range)
  }

  // `id` carries no unique constraint anywhere in NomiCore (R5 — CloudKit
  // doesn't support them), so two devices can genuinely insert
  // `Category`/`Account` rows sharing an id before first sync reconciles
  // them (nothing reconciles Category/Account duplicates the way
  // `IngestPipeline.reconcile()` does for `Transaction`). `uniqueKeysWithValues:`
  // traps on a duplicate key; `uniquingKeysWith:` doesn't. Same guard Park
  // added to `SwiftDataInsightsStore.categoryMap()` for the identical reason.
  private var categoryNamesByID: [UUID: String] {
    Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }

  private var categoryPaletteSlotByID: [UUID: Int] {
    Dictionary(categories.map { ($0.id, $0.paletteSlot) }, uniquingKeysWith: { first, _ in first })
  }

  private var categorySymbolNameByID: [UUID: String] {
    Dictionary(categories.map { ($0.id, $0.symbolName) }, uniquingKeysWith: { first, _ in first })
  }

  private var accountNamesByID: [UUID: String] {
    Dictionary(accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
  }

  /// The transaction list, shared by the scrolling layout and the first-run layout.
  private var transactionList: some View {
      LedgerTransactionList(
        filter: filter,
        range: range,
        now: now,
        periodLabel: periodLabel,
        scope: scope,
        kind: activeSelection,
        isFiltered: isFiltered,
        transactionStore: transactionStore,
        categoryNamesByID: categoryNamesByID,
        categoryPaletteSlotByID: categoryPaletteSlotByID,
        categorySymbolNameByID: categorySymbolNameByID,
        accountNamesByID: accountNamesByID,
        searchMatches: searchResults,
        onSelectTransaction: { id in
          // Drop the whole-ledger rows before the sheet opens. The sheet can
          // delete or edit the row it shows, and a model read after that
          // can trap; the list then falls back to the live period until the
          // sheet closes and the search runs again.
          searchResults = nil
          presented = PresentedTransaction(id: id)
        },
        onMutate: {
          // Same reason as above, for delete and "Mark reviewed" in the
          // context menu: those rows may be in `searchResults`.
          searchResults = nil
          searchGeneration += 1
        },
        onWindowChange: { windowSummary = $0 },
        onClearFilters: clearFilters
      )
      .id(queryKey)
  }

  /// The first-run Ledger (no transactions): the header, then the empty block in
  /// the space the header leaves above the tab bar (D15). Flexible frames split
  /// the visible height, so the block centres in that space with no measurement.
  private var firstRunLayout: some View {
    // The scroll view ends at the tab bar's top, so its visible height is the band
    // the block must fill. `containerRelativeFrame` pins the stack to that height.
    ScrollView {
      VStack(spacing: 0) {
        header
        transactionList
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .containerRelativeFrame(.vertical, alignment: .top) { length, _ in
        LedgerFirstRunBand.height(containerHeight: length, tabBottomReserve: tabBarReserve)
      }
    }
  }

  public var body: some View {
    Group {
    if emptyKind == .empty {
      firstRunLayout
    } else {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
          Color.clear
            .frame(height: 0)
            .id(LedgerScrollTarget.top)

          // The header, with the period pill, stays in the first-run state too: the
          // LedgerEmpty artboard shows it. The search field and chips are hidden there.
          header
          if emptyKind != .empty {
            NomiSearchField(prompt: LedgerCopy.searchPlaceholder, text: $searchText)
              .padding(.horizontal, NomiSpacing.screenGutter)
              .padding(.top, NomiSpacing.xs)
            chipRow
              .padding(.top, NomiSpacing.xs)
          }

          if searchFailed {
            NomiStatusNote(
              LedgerCopy.searchFailedText(periodLabel: scopedPeriodLabel),
              tone: .error,
              systemImage: "exclamationmark.circle"
            )
            .padding(.horizontal, NomiSpacing.screenGutter)
            .padding(.top, NomiSpacing.xs)
          }

          // `.id(queryKey)` is load-bearing: SwiftData's `@Query` fixes its
          // filter at the view instance's construction and never re-evaluates
          // it in place. Only the period changes that predicate, so only the
          // range is in `queryKey` — a chip switch or a search edit updates
          // `filter` in place instead, which `rows` already re-reads without
          // forcing a new instance.
          transactionList

          // Hidden in the true first-run state, and while the list is a queue
          // (Needs review, or a search): a queue takes no period.
          if scope == .period && emptyKind != .empty {
            showPreviousButton(proxy: proxy)
          }
        }
      }
      // The last row clears the floating tab bar (D4). The first-run layout is not
      // given it: its band already ends above the bar (LedgerFirstRunBand).
      .contentMargins(.bottom, tabBarReserve, for: .scrollContent)
    }
    }
    }
    .background(NomiColor.ground)
    // The title is the page header in the content (artboard Activity), so the bar goes.
    #if os(iOS)
      .toolbar(.hidden, for: .navigationBar)
    #endif
    // Sets `now` once per appearance rather than every `dayHeader` call —
    // day headers read it from here, not from a fresh `Date()` in `body`.
    // The Home and Import routes may send a search: its text prefills the box once.
    .onAppear {
      now = Date()
      if let text = prefillGate.take(activityRequest) {
        searchText = text
      }
    }
    // A basis switch re-anchors to the current period, as the menu reads
    // (DEC-04, item 3). The anchor is otherwise kept, so leaving Needs review
    // or a search restores the period that was on screen.
    .onChange(of: basis) { _, _ in
      anchor = now
    }
    .task(id: searchKey) {
      await runSearch(for: searchKey.text)
    }
    .sheet(item: $presented, onDismiss: { searchGeneration += 1 }) { presented in
      TransactionDetailScreen(
        transactionID: presented.id,
        transactionStore: transactionStore,
        editor: editor,
        categoryStore: categoryStore,
        accountStore: accountStore,
        suggester: suggester
      )
      .modelContainer(modelContext.container)
    }
  }

  // MARK: - Whole-ledger search

  /// What the search task is keyed on: the settled query and the reload
  /// counter. Typing changes `text`; closing the detail sheet or changing a
  /// row from the list changes `generation`.
  private struct SearchKey: Hashable {
    let text: String?
    let generation: Int
  }

  private var searchKey: SearchKey {
    SearchKey(text: LedgerSearch.normalized(searchText), generation: searchGeneration)
  }

  /// Runs one search after the debounce. `.task(id:)` cancels the previous
  /// task on each keystroke, so only the last query reaches the store, and a
  /// cancelled wait returns without touching state.
  ///
  /// Between keystrokes `searchResults` still holds the previous query's rows
  /// for up to the debounce plus the fetch, which is a short stale window, not
  /// a wrong answer that persists.
  private func runSearch(for text: String?) async {
    guard let text, let transactionSearch else {
      searchResults = nil
      searchFailed = false
      return
    }
    do {
      try await Task.sleep(nanoseconds: LedgerSearch.debounceNanoseconds)
    } catch {
      return
    }
    do {
      searchResults = try transactionSearch.search(text, limit: LedgerSearch.limit)
      searchFailed = false
    } catch {
      searchResults = nil
      searchFailed = true
    }
  }

  // MARK: - Period

  /// The page header (S2): "Activity" on the left, the period pill on the right, as
  /// the artboard draws it. The pill's menu is Home's shape: a basis picker, a
  /// divider, then the recent periods (DEC-04). While the list is a queue the pill
  /// reads "All time" and is disabled.
  private var header: some View {
    NomiPageHeader("Activity") {
      NomiPeriodPill(title: scope == .period ? periodLabel : "All time", style: .onGround) {
        periodMenu
      }
      .disabled(scope == .wholeLedger)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
  }

  @ViewBuilder
  private var periodMenu: some View {
    Picker("Period basis", selection: $basis) {
      Text("Calendar month").tag(PeriodBasis.calendarMonth)
      Text("Financial year").tag(PeriodBasis.financialYear)
    }
    Divider()
    ForEach(DashboardPeriod.recentAnchors(basis: basis, now: now), id: \.self) { candidate in
      Button(DashboardPeriod.label(for: DashboardPeriod.period(basis: basis, anchor: candidate))) {
        anchor = candidate
      }
    }
  }

  // MARK: - Filter chips

  /// One horizontal row (artboard Activity): All, To review with its warning count,
  /// then Spent, Income and Transfers. A routed category or Uncategorized comes first
  /// as a sixth selected chip, "<name> ✕", and tapping it returns to All. Scrolls
  /// sideways when it overflows, and the gutter is inside the scroll so the first
  /// chip is not clipped at the edge.
  private var chipRow: some View {
    let routed = LedgerChipRow.routedTitle(for: activeSelection, categoryNames: categoryNamesByID)
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: NomiSpacing.xxs) {
        if let routed {
          LedgerChip(title: routed, isSelected: true) {
            selection = .all
          }
        }
        LedgerChip(title: "All", isSelected: activeSelection == .all) {
          selection = .all
        }
        LedgerChip(
          title: "To review",
          count: LedgerChipRow.reviewCount(windowSummary.needsReviewCount),
          isSelected: activeSelection == .needsReview
        ) {
          selection = .needsReview
        }
        LedgerChip(title: "Spent", isSelected: activeSelection == .spent) {
          selection = .spent
        }
        LedgerChip(title: "Income", isSelected: activeSelection == .income) {
          selection = .income
        }
        LedgerChip(title: "Transfers", isSelected: activeSelection == .transfers) {
          selection = .transfers
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
    }
  }

  /// Resets the chip and the search box. The period is not a filter, so it is
  /// kept (DEC-04, item 8).
  private func clearFilters() {
    searchText = ""
    selection = .all
  }

  // MARK: - Paging

  /// At the foot of the list. Steps the period back one, moves the list to its
  /// top, and names the period it will show (DEC-04, item 7). Replaces the
  /// 90-day "Show older": a bounded period needs no paging.
  private func showPreviousButton(proxy: ScrollViewProxy) -> some View {
    let label = LedgerPeriod.previousLabel(basis: basis, anchor: anchor, calendar: .current, now: now)
    return Button(LedgerCopy.showPreviousTitle(label: label)) {
      anchor = LedgerPeriod.previousAnchor(basis: basis, anchor: anchor, calendar: .current, now: now)
      proxy.scrollTo(LedgerScrollTarget.top, anchor: .top)
    }
    .buttonStyle(NomiSecondaryButtonStyle())
    .frame(maxWidth: .infinity)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.vertical, NomiSpacing.sm)
  }
}

/// One chip of the Activity row (artboard `.chip`): the `NomiChip` look, with an
/// optional `NomiTag` count, which `NomiChip` cannot draw (it prints the count as
/// text). 36 pt high with a 44 pt tap area. Selected is navy with white text, and
/// unselected is `card` with a 1 pt `separator` stroke.
private struct LedgerChip: View {
  let title: String
  var count: String?
  let isSelected: Bool
  let action: () -> Void

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: NomiRadius.chip, style: .continuous)
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xxs) {
        Text(title)
          .nomiTextStyle(isSelected ? .chipSelected : .chip)
          .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.ink)
          .lineLimit(1)
        if let count {
          NomiTag(count, tone: .warning)
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 36)
      .background {
        shape.fill(isSelected ? NomiColor.navy : NomiColor.card)
      }
      .overlay {
        if !isSelected {
          shape.strokeBorder(NomiColor.separator, lineWidth: 1)
        }
      }
      .frame(minHeight: NomiSpacing.minTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// The artboard's "Clear filters": a white capsule with a hairline border and
/// a navy label, 44 pt high. `NomiSecondaryButtonStyle` is text alone, with
/// no edge, and reads as a link next to the chips.
private struct LedgerClearFiltersStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.navy)
      .padding(.horizontal, 22)
      .frame(minHeight: NomiSpacing.minTarget)
      .background(Capsule(style: .continuous).fill(NomiColor.card))
      .overlay(Capsule(style: .continuous).strokeBorder(NomiColor.separator, lineWidth: 1))
      .contentShape(Capsule(style: .continuous))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// The transaction list. Its own view, not a computed property on
/// `LedgerScreen`, because a `@Query`'s filter is fixed when the view
/// instance is built and SwiftData does not let it be re-pointed afterwards —
/// so a new period has to construct a new instance of *something*, and
/// `LedgerScreen` gives it one via `.id(queryKey)`. A chip switch or a search
/// edit changes `filter` instead, which `rows` reads on every body
/// re-evaluation of the *same* instance — no new `@Query` needed.
///
/// Two queries. `periodRows` is bounded by the period (`LedgerFilterPredicate.make(range:)`).
/// `flagged` is the Needs review queue, a single comparison with no date bound,
/// so the chip's count and its list are the same all-time set (DEC-04, item 6).
private struct LedgerTransactionList: View {
  let filter: TransactionFilter
  /// The selected period. The list's period query is built from it at init.
  let range: Range<Date>
  let now: Date
  /// The period's label, for the "No transactions in <period> yet" title.
  let periodLabel: String
  /// Which rows the list draws. `.period` names the period in copy; the queues do not.
  let scope: LedgerScope
  /// The chip the list applies. The kind chips (Spent, Income, Transfers) are
  /// applied in memory here, after the predicate; the other chips are in `filter`.
  let kind: LedgerChipSelection
  /// A chip other than All is selected, or the search box holds a query.
  let isFiltered: Bool
  let transactionStore: TransactionStore
  let categoryNamesByID: [UUID: String]
  let categoryPaletteSlotByID: [UUID: Int]
  let categorySymbolNameByID: [UUID: String]
  let accountNamesByID: [UUID: String]
  /// Whole-ledger rows for the current query, or nil for the period list.
  let searchMatches: [NomiCore.Transaction]?
  let onSelectTransaction: (UUID) -> Void
  /// Called after this list deletes or marks a row reviewed, so the parent can
  /// drop any whole-ledger rows it still holds.
  let onMutate: () -> Void
  /// Reports the summary to the parent, which owns the chip row.
  let onWindowChange: (LedgerWindowSummary) -> Void
  /// Resets the chip and the search box from the no-results state.
  let onClearFilters: () -> Void

  @Query private var periodRows: [NomiCore.Transaction]
  /// Sizes the day header's totals: at accessibility sizes the label stacks above them.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Query(
    filter: LedgerFilterPredicate.makeNeedsReview(),
    sort: [SortDescriptor(\NomiCore.Transaction.date, order: .reverse)]
  )
  private var flagged: [NomiCore.Transaction]

  @Environment(\.nomiAddTransaction) private var addTransaction
  @Environment(\.modelContext) private var modelContext

  @State private var pendingDeleteID: UUID?
  @State private var errorMessage: String?

  init(
    filter: TransactionFilter,
    range: Range<Date>,
    now: Date,
    periodLabel: String,
    scope: LedgerScope,
    kind: LedgerChipSelection,
    isFiltered: Bool,
    transactionStore: TransactionStore,
    categoryNamesByID: [UUID: String],
    categoryPaletteSlotByID: [UUID: Int],
    categorySymbolNameByID: [UUID: String],
    accountNamesByID: [UUID: String],
    searchMatches: [NomiCore.Transaction]?,
    onSelectTransaction: @escaping (UUID) -> Void,
    onMutate: @escaping () -> Void,
    onWindowChange: @escaping (LedgerWindowSummary) -> Void,
    onClearFilters: @escaping () -> Void
  ) {
    self.filter = filter
    self.range = range
    self.now = now
    self.periodLabel = periodLabel
    self.scope = scope
    self.kind = kind
    self.isFiltered = isFiltered
    self.transactionStore = transactionStore
    self.categoryNamesByID = categoryNamesByID
    self.categoryPaletteSlotByID = categoryPaletteSlotByID
    self.categorySymbolNameByID = categorySymbolNameByID
    self.accountNamesByID = accountNamesByID
    self.searchMatches = searchMatches
    self.onSelectTransaction = onSelectTransaction
    self.onMutate = onMutate
    self.onWindowChange = onWindowChange
    self.onClearFilters = onClearFilters
    // Only the period is pushed into the period `@Query` itself — see
    // `LedgerFilterPredicate`'s note on why the chip/search criteria are
    // applied below instead, in `rows`.
    _periodRows = Query(
      filter: LedgerFilterPredicate.make(range: range),
      sort: [SortDescriptor(\NomiCore.Transaction.date, order: .reverse)]
    )
  }

  /// The rows the list draws, before grouping. A search reaches the whole
  /// ledger and ignores the period. Needs review is the flagged queue. Otherwise
  /// the selected period. The chip and search rules apply to each.
  private var rows: [NomiCore.Transaction] {
    // The kind chips (Spent, Income, Transfers) are applied to whichever set the
    // branch below draws. Every other chip returns true there.
    let byKind: (NomiCore.Transaction) -> Bool = { LedgerFiltering.kindMatches($0, selection: kind) }
    // A blank box never shows whole-ledger rows, even for the one frame before
    // `runSearch` clears `searchMatches`.
    if let searchMatches, LedgerSearch.normalized(filter.searchText) != nil {
      // The whole-ledger search already matched the text. Only the chip still
      // applies, so the text is cleared here rather than matched twice.
      var chipOnly = filter
      chipOnly.searchText = ""
      return searchMatches.filter { LedgerFilterPredicate.matches($0, filter: chipOnly, within: nil) && byKind($0) }
    }
    if filter.needsReviewOnly {
      return flagged.filter { LedgerFilterPredicate.matches($0, filter: filter, within: nil) }
    }
    return periodRows.filter { LedgerFilterPredicate.matches($0, filter: filter, within: range) && byKind($0) }
  }

  /// The period, not the search: see `LedgerWindowSummary`. `storeHasRows` is
  /// read only when the period is empty, since a non-empty period already proves
  /// the store has rows. `needsReviewCount` is the whole ledger's queue.
  private var summary: LedgerWindowSummary {
    let hasRows = !periodRows.isEmpty
    return LedgerWindowSummary(
      hasRows: hasRows,
      storeHasRows: hasRows || storeHasAnyRow,
      needsReviewCount: flagged.count
    )
  }

  /// Whether the whole table holds any transaction. A one-row fetch, so it
  /// never loads the table (F1). If the fetch throws it answers true, so the
  /// screen says "No transactions in <period> yet" rather than the first-run copy.
  private var storeHasAnyRow: Bool {
    var descriptor = FetchDescriptor<NomiCore.Transaction>()
    descriptor.fetchLimit = 1
    guard let fetched = try? modelContext.fetch(descriptor) else { return true }
    return !fetched.isEmpty
  }

  /// Calendar `.current`, the same calendar `range` and Home use, so a day
  /// group never straddles the period's edge (DEC-04, item 4).
  private var groups: [LedgerDayGroup<NomiCore.Transaction>] {
    LedgerGrouping.byDay(rows, calendar: .current)
  }

  private var addAction: (() -> Void)? {
    guard let addTransaction else { return nil }
    return { addTransaction() }
  }

  var body: some View {
    Group {
      if groups.isEmpty {
        emptyContent
      } else {
        ForEach(groups) { group in
          dayGroup(group)
        }
      }
    }
    .onChange(of: summary, initial: true) { _, newValue in
      onWindowChange(newValue)
    }
    // F9: delete used to be immediate, permanent and unconfirmed, with no
    // undo. This is the same `.confirmationDialog` `TransactionDetailScreen`
    // uses. There is still no undo here — `delete` is a hard delete and
    // CloudKit has already propagated it by the time this dialog could ever
    // reappear; undo needs a soft-delete schema column, a separate ask.
    .alert(
      "Delete this transaction?",
      isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } })
    ) {
      Button("Delete", role: .destructive) { performDelete() }
      Button("Cancel", role: .cancel) {}
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
      presenting: errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  // MARK: - Day groups

  /// One section per day: a sticky header, then the day's rows in one card
  /// with 1 pt dividers between them (none after the last).
  private func dayGroup(_ group: LedgerDayGroup<NomiCore.Transaction>) -> some View {
    let lastIndex = group.rows.count - 1
    return Section {
      VStack(spacing: 0) {
        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, transaction in
          row(for: transaction)
          if index < lastIndex {
            Rectangle()
              .fill(NomiColor.separator)
              .frame(height: 1)
          }
        }
      }
      // The flush card (artboard `.card.flush`): 6 pt above and below, 18 pt at the sides.
      .nomiCard(padding: EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
      .padding(.horizontal, NomiSpacing.screenGutter)
    } header: {
      dayHeader(group)
    }
  }

  // MARK: - Day header

  /// The day label on the left, in ink (artboard), and the day's totals on the
  /// right: spent, received, or both (`LedgerDayTotalText`). A day with neither side
  /// shows no total. Opaque, so content scrolling beneath a pinned header does not
  /// show through.
  private func dayHeader(_ group: LedgerDayGroup<NomiCore.Transaction>) -> some View {
    let totals = LedgerDayTotals.of(group.rows)
    let totalText = LedgerDayTotalText.string(spentMinor: totals.spentMinor, receivedMinor: totals.receivedMinor)
    let label = Text(LedgerDayHeaderText.string(for: group.day, relativeTo: now))
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.ink)
    return Group {
      if dynamicTypeSize.isAccessibilitySize {
        // At accessibility sizes the total takes its own line, so it never shares a
        // row with the label and cannot break across lines.
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          label
          if let totalText {
            dayTotal(totalText)
          }
        }
      } else {
        HStack {
          label
          Spacer(minLength: NomiSpacing.xs)
          if let totalText {
            dayTotal(totalText)
              .layoutPriority(1)
          }
        }
      }
    }
    .frame(minHeight: LedgerMetrics.dayHeaderHeight, alignment: .leading)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.cardGap)
    .padding(.bottom, NomiSpacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Opaque and layered above the card beneath: a pinned header must not show rows
    // through it, at any Dynamic Type size (Lim PR #212, AX3).
    .background(NomiColor.ground)
    .zIndex(1)
  }

  /// A day total on one line. It never wraps mid-amount: it shrinks to fit instead.
  private func dayTotal(_ text: String) -> some View {
    Text(text)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  }

  // MARK: - Rows

  private func row(for transaction: NomiCore.Transaction) -> some View {
    Button {
      onSelectTransaction(transaction.id)
    } label: {
      TransactionRow(
        transaction: transaction,
        categoryName: transaction.categoryID.flatMap { categoryNamesByID[$0] },
        accountName: transaction.accountID.flatMap { accountNamesByID[$0] },
        categorySymbolName: transaction.categoryID.flatMap { categorySymbolNameByID[$0] },
        categoryPaletteSlot: transaction.categoryID.flatMap { categoryPaletteSlotByID[$0] }
      )
      .frame(maxWidth: .infinity, minHeight: LedgerMetrics.rowHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      if transaction.needsReview {
        Button("Mark reviewed") { markReviewed(transaction.id) }
      }
      Button("Delete", role: .destructive) { pendingDeleteID = transaction.id }
    }
  }

  // MARK: - Empty states

  /// `.empty` only when the store has no transactions and no filter is set:
  /// the first-run state. `.nothingRecent` when the period is empty but other
  /// rows exist. `.noResults` when a chip or the search empties the list. Only
  /// `.empty` hides the chip row and search bar, in `LedgerScreen`.
  @ViewBuilder
  private var emptyContent: some View {
    switch LedgerEmptyKind.of(
      hasRows: summary.hasRows, storeHasRows: summary.storeHasRows, isFiltered: isFiltered)
    {
    case .empty:
      // Centred in the space the header leaves above the tab bar (D15); the
      // list's flexible frame gives it that space (`firstRunLayout`).
      NomiEmptyState(
        systemImage: "receipt",
        title: "No transactions yet",
        message: "Transactions appear here once mail is connected, or add one by hand.",
        actionTitle: addAction == nil ? nil : "Add transaction",
        action: addAction
      )
      .padding(.horizontal, NomiSpacing.md)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    case .nothingRecent:
      // The States board's empty copy, with its one next step (S2 step 6).
      NomiEmptyState(
        systemImage: "tray",
        title: LedgerCopy.nothingInPeriodTitle(label: periodLabel),
        message: LedgerCopy.nothingInPeriodMessage,
        actionTitle: addAction == nil ? nil : "Add a transaction",
        action: addAction
      )
      .padding(.horizontal, NomiSpacing.md)
      .padding(.top, NomiSpacing.lg)
    case .noResults:
      noResults
    case .none:
      EmptyView()
    }
  }

  private var noResults: some View {
    VStack(spacing: 0) {
      NomiEmptyState(
        systemImage: "magnifyingglass",
        title: LedgerCopy.noResultsTitle(query: filter.searchText),
        message: LedgerCopy.noResultsMessage(periodLabel: scope == .period ? periodLabel : nil)
      )
      Button("Clear filters", action: onClearFilters)
        .buttonStyle(LedgerClearFiltersStyle())
        .padding(.top, NomiSpacing.md)
    }
    .padding(.horizontal, NomiSpacing.md)
    .padding(.top, NomiSpacing.lg)
  }

  // MARK: - Actions

  private func markReviewed(_ id: UUID) {
    do {
      try transactionStore.dismissReview(id)
      onMutate()
    } catch {
      errorMessage = "Could not mark this reviewed."
    }
  }

  private func performDelete() {
    guard let id = pendingDeleteID else { return }
    pendingDeleteID = nil
    do {
      try transactionStore.delete(id)
      onMutate()
    } catch {
      errorMessage = "Could not delete this transaction."
    }
  }
}

// MARK: - Previews

/// M4: the canonical preview for verifying the row-tap → sheet wiring — tap
/// any row and the detail sheet should open populated, proving
/// `.modelContainer(modelContext.container)` actually reaches the sheet's own
/// `@Query` rather than trapping at runtime the way an uninherited container
/// would (CI cannot catch that; only opening this preview and tapping a row
/// can).
#Preview("Ledger — populated") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor()
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.light)
}

#Preview("Ledger — empty") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(transactions: []), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(transactions: [])
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: []))
  .preferredColorScheme(.light)
}

#Preview("Ledger — single day") {
  let transactions = LedgerPreviewSupport.singleDayTransactions()
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(transactions: transactions), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(transactions: transactions)
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.light)
}

#Preview("Ledger — month spanning a year boundary") {
  let transactions = LedgerPreviewSupport.yearBoundaryTransactions()
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(transactions: transactions), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(transactions: transactions)
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.light)
}

/// `.constant(true)` rather than exercising the real row's `@State` — that
/// state is private to `LedgerTransactionList` and there is no existing
/// precedent in this codebase for seeding another view's presented-sheet
/// state from a preview. This shows the exact title/actions the real dialog
/// presents, standalone.
#Preview("Ledger — delete confirmation") {
  Text("SWIGGY/PAYMENT/REF1")
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.ink)
    .padding()
    .background(NomiColor.card)
    .alert("Delete this transaction?", isPresented: .constant(true)) {
      Button("Delete", role: .destructive) {}
      Button("Cancel", role: .cancel) {}
    }
    .preferredColorScheme(.light)
}

#Preview("Ledger — delete error alert") {
  Text("SWIGGY/PAYMENT/REF1")
    .nomiTextStyle(.body)
    .foregroundStyle(NomiColor.ink)
    .padding()
    .background(NomiColor.card)
    .alert("Something went wrong", isPresented: .constant(true)) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Could not delete this transaction.")
    }
    .preferredColorScheme(.light)
}

/// W1-6: `PreviewData.transactions` includes at least one `needsReview: true`
/// row, so this chip has something to show without a bespoke fixture.
#Preview("Ledger — needs review chip selected") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(), initialChip: .needsReview
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.light)
}

/// The no-results state: a chip is selected and it matches nothing. The
/// artboard's search-and-filter copy shows here too.
#Preview("Ledger — needs review chip, no results") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(transactions: []), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(transactions: []), initialChip: .needsReview
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: []))
  .preferredColorScheme(.light)
}

#Preview("Ledger — accessibility 3") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor()
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
