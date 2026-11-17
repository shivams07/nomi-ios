import NomiCore
import NomiPreview
import SwiftUI

/// Anything with a `date` can be ranked by recency. Kept separate from
/// `Transaction` so the sort/limit logic below is testable with no container —
/// not because this package's runner cannot build one, which it can under
/// XCTest (see `InMemoryModelContainer`'s measured note in NomiCore).
/// `Transaction`'s conformance costs nothing extra; it only reads
/// an existing `date` property, never constructs one.
protocol DatedRow {
  var date: Date { get }
}

extension NomiCore.Transaction: DatedRow {}

enum RecentRows {
  static func mostRecent<T: DatedRow>(_ rows: [T], limit: Int) -> [T] {
    Array(rows.sorted { $0.date > $1.date }.prefix(limit))
  }
}

/// `RecentTransactionsCard`'s badge dictionary — `uniquingKeysWith` first
/// wins because duplicate ids exist on two-device stores (the ledger's own
/// guard, mirrored here rather than assumed away).
enum RecentBadges {
  static func lookup(_ categories: [CategoryBadge]) -> [UUID: CategoryBadge] {
    Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }
}

/// S1b step 6. The most recent transactions on Home, each drawn with F2b's
/// `TransactionRow`, so a Home row reads like a Ledger row. Each row opens the
/// Detail sheet through `onSelect`. The "Recent" header is drawn by
/// `DashboardView`, so the card has no title of its own.
public struct RecentTransactionsCard: View {
  /// Home shows four rows. The read takes five (`DashboardWiring`), and the card
  /// keeps four.
  public static let rowLimit = 4

  public let transactions: [NomiCore.Transaction]
  public let badges: [UUID: CategoryBadge]
  /// Account names by id. A row whose account is not here reads "Unassigned".
  public let accountNames: [UUID: String]
  public let onSelect: ((UUID) -> Void)?

  public init(
    transactions: [NomiCore.Transaction],
    badges: [UUID: CategoryBadge] = [:],
    accountNames: [UUID: String] = [:],
    onSelect: ((UUID) -> Void)? = nil
  ) {
    self.transactions = transactions
    self.badges = badges
    self.accountNames = accountNames
    self.onSelect = onSelect
  }

  private var recent: [NomiCore.Transaction] {
    RecentRows.mostRecent(transactions, limit: Self.rowLimit)
  }

  public var body: some View {
    if recent.isEmpty {
      Text("No transactions yet")
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
        .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    } else {
      VStack(spacing: 0) {
        ForEach(Array(recent.enumerated()), id: \.element.id) { index, transaction in
          row(for: transaction, showsDivider: index < recent.count - 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
  }

  /// One `TransactionRow`, as a button. The 1 pt divider is an overlay on the
  /// row's bottom edge, so the row keeps its height with or without it.
  private func row(for transaction: NomiCore.Transaction, showsDivider: Bool) -> some View {
    let badge = transaction.categoryID.flatMap { badges[$0] }
    let accountName = transaction.accountID.flatMap { accountNames[$0] }
    return Button {
      onSelect?(transaction.id)
    } label: {
      TransactionRow(
        transaction: transaction,
        categoryName: badge?.name,
        accountName: accountName,
        categorySymbolName: badge?.symbolName,
        categoryPaletteSlot: badge?.paletteSlot
      )
      .overlay(alignment: .bottom) {
        if showsDivider {
          Rectangle()
            .fill(NomiColor.separator)
            .frame(height: 1)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview("Recent · default") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Recent · empty") {
  RecentTransactionsCard(transactions: [])
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Recent · accessibility 3") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
