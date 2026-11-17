import NomiCore
import SwiftUI

/// A category's budget this month, as the grid reads it.
struct CategoryGridBudget: Equatable {
  let budgetMinor: Int
  let spentMinor: Int
}

/// One "Where it went" tile (S1b step 4): a category's name and icon, its amount,
/// and a caption that says what is left of its budget, how far over it is, or
/// what share of spending it is.
struct CategoryGridTile: Equatable, Identifiable {
  let id: UUID
  let name: String
  let symbolName: String
  let paletteSlot: Int
  let amountMinor: Int
  /// The category's share of this period's spending, whole percent.
  let sharePercent: Int
  /// Present when the category has a budget this month. Budgets are monthly, so
  /// the grid has none on a financial-year basis.
  let budget: CategoryGridBudget?

  /// The uncategorised slice has no category to open, so its tap goes to the
  /// Uncategorized filter.
  var isUncategorised: Bool {
    id == NomiCore.Category.uncategorizedID
  }

  /// A tap opens the Ledger filtered to this category (`nomiShowLedger(.category)`).
  var destination: ActivityRequest {
    isUncategorised ? .uncategorized : .category(id)
  }

  /// Spending past the budget. Only a budgeted tile can be over.
  var isOver: Bool {
    guard let budget else { return false }
    return budget.spentMinor > budget.budgetMinor
  }

  /// The bar's state, from `NomiBudgetState`'s integer rule. `nil` without a budget.
  var budgetState: NomiBudgetState? {
    guard let budget else { return nil }
    return NomiBudgetState.of(spentMinor: budget.spentMinor, budgetMinor: budget.budgetMinor)
  }

  /// "₹41.00 left of ₹5,000.00", "₹965.00 over ₹2,600.00", or "51% of spending".
  var caption: String {
    guard let budget else {
      return String(localized: "\(sharePercent)% of spending", bundle: .module)
    }
    let budgetText = NomiFormatters.amountString(minor: budget.budgetMinor)
    if isOver {
      let over = NomiFormatters.amountString(minor: budget.spentMinor - budget.budgetMinor)
      return String(localized: "\(over) over \(budgetText)", bundle: .module)
    }
    let left = NomiFormatters.amountString(minor: budget.budgetMinor - budget.spentMinor)
    return String(localized: "\(left) left of \(budgetText)", bundle: .module)
  }
}

/// The tiles for the grid, pure so the tests can reach them.
enum CategoryGridLogic {
  /// The grid shows four tiles at most.
  static let limit = 4

  /// The top categories by spend, largest first. A category with no spend this
  /// period is not "where it went", so it is left out. A budget is matched by
  /// category id, since `BudgetProgress.id` is the category's id.
  static func tiles(slices: [CategorySlice], budgets: [BudgetProgress]) -> [CategoryGridTile] {
    let budgetByID = Dictionary(budgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let ranked = slices
      .filter { $0.totalMinor > 0 }
      .sorted { lhs, rhs in
        if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
        return lhs.id.uuidString < rhs.id.uuidString
      }
    return ranked.prefix(limit).map { slice in
      let budget = budgetByID[slice.id].map {
        CategoryGridBudget(budgetMinor: $0.budgetMinor, spentMinor: $0.spentMinor)
      }
      return CategoryGridTile(
        id: slice.id,
        name: slice.name,
        symbolName: slice.symbolName,
        paletteSlot: slice.paletteSlot,
        amountMinor: slice.totalMinor,
        sharePercent: Int((slice.share * 100).rounded()),
        budget: budget
      )
    }
  }
}

/// "Where it went" on Home (S1b step 4). The header has no "See all": Insights is
/// one tap away (Corrections 9). Each tile opens its category in the Ledger.
/// The grid is hidden when there is nothing to show.
struct CategoryGridCard: View {
  let tiles: [CategoryGridTile]
  /// Opens the Ledger filtered to a request. `nil` draws the tiles as reads.
  let onOpen: ((ActivityRequest) -> Void)?

  private let columns = [
    GridItem(.flexible(), spacing: 12, alignment: .top),
    GridItem(.flexible(), spacing: 12, alignment: .top),
  ]

  var body: some View {
    if !tiles.isEmpty {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        Text("Where it went", bundle: .module)
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
          .accessibilityAddTraits(.isHeader)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
          ForEach(tiles) { tile in
            tileView(tile)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func tileView(_ tile: CategoryGridTile) -> some View {
    if let onOpen {
      Button {
        onOpen(tile.destination)
      } label: {
        tileCard(tile)
      }
      .buttonStyle(.plain)
    } else {
      tileCard(tile)
    }
  }

  private func tileCard(_ tile: CategoryGridTile) -> some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        HStack(alignment: .center, spacing: NomiSpacing.xs) {
          Text(tile.name)
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.dayHeader)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
          NomiCategoryBadge(symbolName: tile.symbolName, paletteSlot: tile.paletteSlot, size: 32)
        }
        NomiAmountText(minor: tile.amountMinor, style: .amountLarge)
        if let budget = tile.budget, let state = tile.budgetState {
          NomiProgressBar(
            fraction: budget.budgetMinor > 0 ? Double(budget.spentMinor) / Double(budget.budgetMinor) : 0,
            state: state,
            height: 6
          )
        }
        Text(tile.caption)
          .nomiTextStyle(.footnote)
          .foregroundStyle(tile.isOver ? NomiColor.error : NomiColor.inkSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .contentShape(Rectangle())
  }
}

#Preview("Where it went · four tiles") {
  CategoryGridCard(
    tiles: CategoryGridLogic.tiles(
      slices: [
        CategorySlice(id: UUID(), name: "Rent", symbolName: "house", paletteSlot: 0, totalMinor: 1_800_000, share: 0.51),
        CategorySlice(id: UUID(), name: "Shopping", symbolName: "bag", paletteSlot: 1, totalMinor: 495_900, share: 0.14),
        CategorySlice(id: UUID(), name: "Ride-hailing", symbolName: "car", paletteSlot: 2, totalMinor: 356_500, share: 0.10),
        CategorySlice(id: UUID(), name: "Groceries", symbolName: "cart", paletteSlot: 3, totalMinor: 214_000, share: 0.06),
      ],
      budgets: []
    ),
    onOpen: { _ in }
  )
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
