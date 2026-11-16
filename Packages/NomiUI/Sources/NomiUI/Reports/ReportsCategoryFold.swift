import Foundation
import NomiCore
import SwiftUI

/// The By category card's rows (S6). The four largest categories get a row and
/// a rank colour. Uncategorised is always its own row, in amber, whatever its
/// size. Every other category folds into one "<n> more categories" row.
enum ReportsCategoryFold {
  /// Stable identity for a folded overflow slice. `ReviewQueueLogic` (S4) reads
  /// it to keep the overflow out of the review tiles.
  static let otherOverflowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000fe")!

  /// How many categories get their own row and rank colour.
  static let rankedRowLimit = 4

  enum RowKind: Equatable {
    /// A categorised row, `rank` 0 being the largest.
    case category(rank: Int)
    case uncategorised
    /// The folded rest: `count` categories.
    case folded(count: Int)
  }

  struct Row: Equatable, Identifiable {
    let id: UUID
    let kind: RowKind
    /// The category's own name. Empty for the uncategorised and folded rows,
    /// whose labels the view localises.
    let categoryName: String
    let totalMinor: Int
    /// The row's part of the period's total, 0...1.
    let share: Double
  }

  struct Breakdown: Equatable {
    let rows: [Row]
    /// Every counted category, Uncategorised included.
    let totalMinor: Int
  }

  /// The rows for a period's category slices. Slices with no spend are skipped.
  static func breakdown(_ slices: [CategorySlice]) -> Breakdown {
    let live = slices.filter { $0.totalMinor > 0 }
    let total = live.reduce(0) { $0 + $1.totalMinor }
    guard total > 0 else { return Breakdown(rows: [], totalMinor: 0) }

    func share(_ minor: Int) -> Double {
      Double(minor) / Double(total)
    }

    let categorised = live
      .filter { $0.id != NomiCore.Category.uncategorizedID }
      .sorted(by: rankPrecedes)
    let uncategorised = live
      .filter { $0.id == NomiCore.Category.uncategorizedID }
      .reduce(0) { $0 + $1.totalMinor }

    var rows: [Row] = []
    for (rank, slice) in categorised.prefix(rankedRowLimit).enumerated() {
      rows.append(Row(
        id: slice.id,
        kind: .category(rank: rank),
        categoryName: slice.name,
        totalMinor: slice.totalMinor,
        share: share(slice.totalMinor)
      ))
    }
    if uncategorised > 0 {
      rows.append(Row(
        id: NomiCore.Category.uncategorizedID,
        kind: .uncategorised,
        categoryName: "",
        totalMinor: uncategorised,
        share: share(uncategorised)
      ))
    }
    let rest = categorised.dropFirst(rankedRowLimit)
    if !rest.isEmpty {
      let restTotal = rest.reduce(0) { $0 + $1.totalMinor }
      rows.append(Row(
        id: otherOverflowID,
        kind: .folded(count: rest.count),
        categoryName: "",
        totalMinor: restTotal,
        share: share(restTotal)
      ))
    }
    return Breakdown(rows: rows, totalMinor: total)
  }

  /// Largest first. Ties go to the name, then the id, so the order is stable.
  private static func rankPrecedes(_ lhs: CategorySlice, _ rhs: CategorySlice) -> Bool {
    if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  /// The colour of a row's dot and its stacked-bar segment. Uncategorised is
  /// always amber. Ranks 0 to 3 take m900, m700, m500 and m300. Anything lower
  /// (the folded rest) is grey: `inkSecondary` at 30%, as the artboard's C9CFC6
  /// has no token.
  static func colour(rank: Int, isUncategorised: Bool) -> Color {
    if isUncategorised { return NomiColor.warningFill }
    switch rank {
    case 0: return NomiColor.navyDeep
    case 1: return NomiColor.navy
    case 2: return NomiColor.blueMid
    case 3: return NomiColor.chartTintMid
    default: return NomiColor.inkSecondary.opacity(0.3)
    }
  }

  static func colour(for kind: RowKind) -> Color {
    switch kind {
    case .category(let rank):
      return colour(rank: rank, isUncategorised: false)
    case .uncategorised:
      return colour(rank: 0, isUncategorised: true)
    case .folded:
      return colour(rank: rankedRowLimit, isUncategorised: false)
    }
  }

  /// Whole percent of the total, rounded half up.
  static func percent(_ share: Double) -> Int {
    Int((share * 100).rounded())
  }
}

/// Whole-rupee text for the category and merchant rows, which show no paise.
enum ReportsRupees {
  /// "₹18,000". The paise round half up to the rupee, and grouping is en_IN's
  /// (lakh and crore).
  static func whole(minor: Int) -> String {
    let rupees = (abs(minor) + 50) / 100
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .decimal
    let digits = formatter.string(from: NSNumber(value: rupees)) ?? "\(rupees)"
    return (minor < 0 ? "\u{2212}" : "") + "₹" + digits
  }
}
