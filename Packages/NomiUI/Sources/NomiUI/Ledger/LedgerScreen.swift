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

/// The Ledger screen (U14) — the transaction list the UI direction specified
/// and no unit was ever given (design §2.19(2)). A tab-root screen like
/// `DashboardView`, not a pushed one: no `NavigationStack`/`.navigationTitle`
/// of its own, `NomiTabShell` supplies the chrome.
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
/// **F1 (fix plan unit 5b):** the transaction table itself is never read
/// whole. `LedgerTransactionList` below owns the `@Query` over
/// `NomiCore.Transaction` and builds its filter from `since`, a rolling
/// 90-day-per-step boundary (`LedgerWindow.since`) — see that type for why it
/// has to be a separate view.
public struct LedgerScreen: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore
  public let accountStore: AccountStore
  public let editor: TransactionEditing

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var accounts: [NomiCore.Account]

  @State private var selection: LedgerChipSelection = .all
  @State private var stepsBack = 0
  @State private var now = Date()

  public init(
    transactionStore: TransactionStore,
    categoryStore: CategoryStore,
    accountStore: AccountStore,
    editor: TransactionEditing
  ) {
    self.transactionStore = transactionStore
    self.categoryStore = categoryStore
    self.accountStore = accountStore
    self.editor = editor
  }

  private var since: Date {
    LedgerWindow.since(for: stepsBack, now: now)
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

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        chipRow
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.vertical, NomiSpacing.sm)

        // `.id(since)` is load-bearing: SwiftData's `@Query` fixes its filter
        // at the view instance's construction and never re-evaluates it
        // in place. Widening the window has to build a new instance — and a
        // new `@Query` — rather than mutate one already committed to the old
        // bound, which is exactly what a changed `.id` forces.
        LedgerTransactionList(
          since: since,
          selection: selection,
          now: now,
          transactionStore: transactionStore,
          categoryNamesByID: categoryNamesByID,
          categoryPaletteSlotByID: categoryPaletteSlotByID,
          categorySymbolNameByID: categorySymbolNameByID,
          accountNamesByID: accountNamesByID
        )
        .id(since)

        showOlderButton
      }
    }
    .background(NomiColor.surfaceCanvas)
    // Sets `now` once per appearance rather than every `dayHeader` call —
    // day headers read it from here, not from a fresh `Date()` in `body`.
    .onAppear { now = Date() }
    .navigationDestination(for: UUID.self) { transactionID in
      TransactionDetailScreen(
        transactionID: transactionID,
        transactionStore: transactionStore,
        editor: editor,
        categoryStore: categoryStore,
        accountStore: accountStore
      )
    }
  }

  // MARK: - Filter chips

  private var chipRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: NomiSpacing.xs) {
        chip(label: "All", systemImage: nil, tint: nil, isSelected: selection == .all) {
          selection = .all
        }
        ForEach(categories) { category in
          chip(
            label: category.name,
            systemImage: category.symbolName,
            tint: paletteSlot(category.paletteSlot),
            isSelected: selection == .category(category.id)
          ) {
            selection = .category(category.id)
          }
        }
        chip(
          label: "Uncategorized", systemImage: "questionmark", tint: CategoryPalette.other,
          isSelected: selection == .uncategorized
        ) {
          selection = .uncategorized
        }
      }
    }
  }

  private func chip(
    label: String, systemImage: String?, tint: Color?, isSelected: Bool, action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: NomiSpacing.xxs) {
      if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(tint ?? NomiColor.textSecondary)
      }
      Text(label)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textPrimary)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, NomiSpacing.xs)
    .background(isSelected ? NomiColor.accent : NomiColor.glassFill)
    .overlay(Capsule(style: .continuous).stroke(NomiColor.glassHairline, lineWidth: 1))
    .clipShape(Capsule(style: .continuous))
    .contentShape(Capsule(style: .continuous))
    .onTapGesture(perform: action)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  // MARK: - Paging

  /// Unconditional, at the foot of the list — this screen never queries
  /// beyond `since` to find out whether there's anything older to show, since
  /// doing so would be exactly the whole-table read F1 exists to remove.
  private var showOlderButton: some View {
    Button {
      stepsBack += 1
    } label: {
      Text("Show older")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.accent)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.vertical, NomiSpacing.sm)
  }
}

/// The windowed transaction list. Its own view, not a computed property on
/// `LedgerScreen`, because a `@Query`'s filter is fixed when the view
/// instance is built and SwiftData does not let it be re-pointed afterwards —
/// so a widening window has to construct a new instance of *something*, and
/// `LedgerScreen` gives it a new one via `.id(since)`.
private struct LedgerTransactionList: View {
  let selection: LedgerChipSelection
  let now: Date
  let transactionStore: TransactionStore
  let categoryNamesByID: [UUID: String]
  let categoryPaletteSlotByID: [UUID: Int]
  let categorySymbolNameByID: [UUID: String]
  let accountNamesByID: [UUID: String]

  @Query private var transactions: [NomiCore.Transaction]

  init(
    since: Date,
    selection: LedgerChipSelection,
    now: Date,
    transactionStore: TransactionStore,
    categoryNamesByID: [UUID: String],
    categoryPaletteSlotByID: [UUID: Int],
    categorySymbolNameByID: [UUID: String],
    accountNamesByID: [UUID: String]
  ) {
    self.selection = selection
    self.now = now
    self.transactionStore = transactionStore
    self.categoryNamesByID = categoryNamesByID
    self.categoryPaletteSlotByID = categoryPaletteSlotByID
    self.categorySymbolNameByID = categorySymbolNameByID
    self.accountNamesByID = accountNamesByID
    _transactions = Query(
      filter: #Predicate<NomiCore.Transaction> { $0.date >= since },
      sort: [SortDescriptor(\NomiCore.Transaction.date, order: .reverse)]
    )
  }

  private var filtered: [NomiCore.Transaction] {
    LedgerFiltering.apply(transactions, selection: selection)
  }

  private var maxAmountMinor: Int {
    filtered.map { abs($0.amountMinor) }.max() ?? 0
  }

  private var groups: [LedgerDayGroup<NomiCore.Transaction>] {
    LedgerGrouping.byDay(filtered)
  }

  var body: some View {
    if groups.isEmpty {
      emptyState
    } else {
      ForEach(groups) { group in
        Section {
          ForEach(group.rows) { transaction in
            row(for: transaction)
          }
        } header: {
          dayHeader(group)
        }
      }
    }
  }

  // MARK: - Day header

  private func dayHeader(_ group: LedgerDayGroup<NomiCore.Transaction>) -> some View {
    HStack {
      Text(LedgerDayHeaderText.string(for: group.day, relativeTo: now))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textSecondary)
      Spacer()
      Text(LedgerDayTotalText.string(minor: group.totalMinor))
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
        .foregroundStyle(NomiColor.textPrimary)
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.vertical, NomiSpacing.xs)
    // Opaque so pinned content beneath doesn't show through while this
    // sticks — canvas colour, not the row colour, since the header sits
    // above the row stack, not inside it.
    .background(NomiColor.surfaceCanvas)
  }

  // MARK: - Rows

  private func row(for transaction: NomiCore.Transaction) -> some View {
    let slot = transaction.categoryID.flatMap { categoryPaletteSlotByID[$0] }
    let symbolName = transaction.categoryID.flatMap { categorySymbolNameByID[$0] }
    let barColor = slot.map(paletteSlot) ?? CategoryPalette.other
    let fraction = LedgerMagnitude.fraction(amountMinor: transaction.amountMinor, maxAmountMinor: maxAmountMinor)

    return NavigationLink(value: transaction.id) {
      VStack(alignment: .leading, spacing: 0) {
        TransactionRow(
          transaction: transaction,
          categoryName: transaction.categoryID.flatMap { categoryNamesByID[$0] },
          accountName: transaction.accountID.flatMap { accountNamesByID[$0] },
          categorySymbolName: symbolName,
          categoryPaletteSlot: slot
        )

        GeometryReader { proxy in
          Rectangle()
            .fill(barColor.opacity(0.35))
            .frame(width: proxy.size.width * max(fraction, 0.02))
        }
        .frame(height: 2)
        .padding(.bottom, NomiSpacing.xxs)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .background(NomiColor.surfaceRow)
      .nomiCornerRadius(NomiRadius.tile)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.bottom, NomiSpacing.xs)
    .contextMenu {
      if transaction.needsReview {
        Button("Mark reviewed") { try? transactionStore.dismissReview(transaction.id) }
      }
      Button("Delete", role: .destructive) { try? transactionStore.delete(transaction.id) }
    }
  }

  private var emptyState: some View {
    Text("No transactions yet")
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.top, NomiSpacing.lg)
  }
}

// MARK: - Previews

#Preview("Ledger — populated, dark") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor()
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Ledger — empty, dark") {
  NomiTabShell {
    NavigationStack {
      LedgerScreen(
        transactionStore: FakeTransactionStore(transactions: []), categoryStore: FakeCategoryStore(),
        accountStore: FakeAccountStore(), editor: FakeTransactionEditor(transactions: [])
      )
    }
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: []))
  .preferredColorScheme(.dark)
}

#Preview("Ledger — single day, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Ledger — month spanning a year boundary, dark") {
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
  .preferredColorScheme(.dark)
}

#Preview("Ledger — accessibility 3, dark") {
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
  .preferredColorScheme(.dark)
}
