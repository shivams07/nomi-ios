import Foundation
import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Ledger screen (U14) — the transaction list the UI direction specified
/// and no unit was ever given (design §2.19(2)). A tab-root screen like
/// `DashboardView`, not a pushed one: no `NavigationStack`/`.navigationTitle`
/// of its own, `NomiTabShell` supplies the chrome.
///
/// Reads transactions/categories/accounts via `@Query` directly against the
/// `@Model` types (design's read/write asymmetry — see `CategoriesScreen`)
/// and takes `transactionStore`/`categoryStore` by init like every other
/// screen, for the one write action this screen offers: dismissing a
/// needs-review row or deleting a mis-imported one, both via `contextMenu`
/// (`.swipeActions` is iOS-only and this package's `swift test` also builds
/// for plain macOS — see `AccountsScreen`). `categoryStore` has no create/
/// rename/delete affordance here — that stays `CategoriesScreen`'s job —
/// but is accepted for the same construction contract as every other screen.
public struct LedgerScreen: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore

  @Query(sort: \NomiCore.Transaction.date, order: .reverse) private var transactions: [NomiCore.Transaction]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var accounts: [NomiCore.Account]

  @State private var selection: LedgerChipSelection = .all

  public init(transactionStore: TransactionStore, categoryStore: CategoryStore) {
    self.transactionStore = transactionStore
    self.categoryStore = categoryStore
  }

  private var categoryNamesByID: [UUID: String] {
    Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
  }

  private var categoryPaletteSlotByID: [UUID: Int] {
    Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.paletteSlot) })
  }

  private var accountNamesByID: [UUID: String] {
    Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.displayName) })
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

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        chipRow
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.vertical, NomiSpacing.sm)

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
    }
    .background(NomiColor.surfaceCanvas)
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

  // MARK: - Day header

  private func dayHeader(_ group: LedgerDayGroup<NomiCore.Transaction>) -> some View {
    HStack {
      Text(NomiFormatters.dayMonth.string(from: group.day))
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
    // sticks — canvas colour, not the (interim) row colour, since the
    // header sits above the row stack, not inside it.
    .background(NomiColor.surfaceCanvas)
  }

  // MARK: - Rows

  private func row(for transaction: NomiCore.Transaction) -> some View {
    let slot = transaction.categoryID.flatMap { categoryPaletteSlotByID[$0] }
    let barColor = slot.map(paletteSlot) ?? CategoryPalette.other
    let fraction = LedgerMagnitude.fraction(amountMinor: transaction.amountMinor, maxAmountMinor: maxAmountMinor)

    return VStack(alignment: .leading, spacing: 0) {
      TransactionRow(
        transaction: transaction,
        categoryName: transaction.categoryID.flatMap { categoryNamesByID[$0] },
        accountName: transaction.accountID.flatMap { accountNamesByID[$0] }
      )
      .padding(.horizontal, NomiSpacing.screenGutter)

      GeometryReader { proxy in
        Rectangle()
          .fill(barColor.opacity(0.35))
          .frame(width: proxy.size.width * max(fraction, 0.02))
      }
      .frame(height: 2)
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.bottom, NomiSpacing.xxs)

      Rectangle()
        .fill(NomiColor.separator)
        .frame(height: 1)
    }
    // NomiColor has no `surface-row` (#1C1C1C) token yet — DESIGN.md/the
    // design doc names it for exactly this row background but it was never
    // added to Design/** (frozen since U5). Escalated to Andrews; using
    // `surfaceRaised` as the closest existing frozen token in the interim.
    .background(NomiColor.surfaceRaised)
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
    LedgerScreen(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Ledger — empty, dark") {
  NomiTabShell {
    LedgerScreen(transactionStore: FakeTransactionStore(transactions: []), categoryStore: FakeCategoryStore())
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: []))
  .preferredColorScheme(.dark)
}

#Preview("Ledger — single day, dark") {
  let transactions = LedgerPreviewSupport.singleDayTransactions()
  NomiTabShell {
    LedgerScreen(transactionStore: FakeTransactionStore(transactions: transactions), categoryStore: FakeCategoryStore())
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

#Preview("Ledger — month spanning a year boundary, dark") {
  let transactions = LedgerPreviewSupport.yearBoundaryTransactions()
  NomiTabShell {
    LedgerScreen(transactionStore: FakeTransactionStore(transactions: transactions), categoryStore: FakeCategoryStore())
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

#Preview("Ledger — accessibility 3, dark") {
  NomiTabShell {
    LedgerScreen(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
