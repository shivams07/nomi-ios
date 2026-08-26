import NomiCore
import NomiPreview
import SwiftUI

/// Anything with a `date` can be ranked by recency. Kept separate from
/// `Transaction` so the sort/limit logic below is testable without
/// constructing an `@Model` instance — this package's `swift test` runner
/// cannot do that headlessly (see `InMemoryModelContainer`'s note in
/// NomiCore). `Transaction`'s conformance costs nothing extra; it only reads
/// an existing `date` property, never constructs one.
protocol DatedRow {
  var date: Date { get }
}

extension Transaction: DatedRow {}

enum RecentRows {
  static func mostRecent<T: DatedRow>(_ rows: [T], limit: Int) -> [T] {
    Array(rows.sorted { $0.date > $1.date }.prefix(limit))
  }
}

/// Card 7 (v5): the 5 most recent rows across all accounts, newest first.
/// Distinct AC from `TopMerchantsCard` — a list of individual rows, not a
/// rollup. Merchant labels use `merchantName ?? descriptionText` (§2.4).
public struct RecentTransactionsCard: View {
  public let transactions: [Transaction]

  public init(transactions: [Transaction]) {
    self.transactions = transactions
  }

  private var recent: [Transaction] {
    RecentRows.mostRecent(transactions, limit: 5)
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Recent transactions")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if recent.isEmpty {
          Text("No transactions yet")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          VStack(spacing: NomiSpacing.xs) {
            ForEach(recent) { transaction in
              row(for: transaction)
            }
          }
        }
      }
    }
  }

  private func row(for transaction: Transaction) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text(transaction.merchantName ?? transaction.descriptionText)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
          .lineLimit(1)
        Text(NomiFormatters.dayMonth.string(from: transaction.date))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer(minLength: NomiSpacing.xs)
      Text(Self.amountText(minor: transaction.amountMinor, direction: transaction.direction))
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
        .foregroundStyle(transaction.direction == .credit ? NomiColor.creditText : NomiColor.debitText)
    }
  }

  static func amountText(minor: Int, direction: Direction) -> String {
    (direction == .credit ? "+" : "") + NomiFormatters.amountString(minor: minor)
  }
}

#Preview("Recent transactions — default, dark") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Recent transactions — empty, dark") {
  RecentTransactionsCard(transactions: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Recent transactions — accessibility 3, dark") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
