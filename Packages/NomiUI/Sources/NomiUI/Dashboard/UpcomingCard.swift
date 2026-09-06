import NomiCore
import NomiPreview
import SwiftUI

/// Sort-and-cap logic pulled out of `body` for the same reason
/// `RecentRows.mostRecent` next door is: `swift test` can reach a pure
/// function, never `UpcomingCard.body`. `RecurringInsightsStore`'s own doc
/// comment says a caller "may rely on" `nextExpected`-ascending order and
/// need not re-sort defensively — this sorts anyway, same defensive-by-
/// convention choice `RecentRows.mostRecent` already makes for
/// `InsightsStore.recentTransactions`, and the one this unit's own tests
/// pin down.
enum UpcomingRows {
  static let limit = 5

  static func soonest(_ series: [RecurringSeries]) -> [RecurringSeries] {
    Array(series.sorted { $0.nextExpected < $1.nextExpected }.prefix(limit))
  }
}

/// U17b. Reads `RecurringInsightsStore` (U17a) through `DashboardView`, which
/// resolves it to a `Load<[RecurringSeries]>?` — `nil` when there is no
/// store at all (this card is absent then, never constructed; see
/// `DashboardView`'s `recurringStore`), so every value this type receives
/// already came from a successful read.
///
/// Every row is a debit by construction (`RecurrenceDetector` only ever
/// groups debits), so the amount is always shown in `debitText` — there is
/// no direction to branch on the way `RecentTransactionsCard` does.
public struct UpcomingCard: View {
  public let series: [RecurringSeries]

  public init(series: [RecurringSeries]) {
    self.series = series
  }

  private var upcoming: [RecurringSeries] {
    UpcomingRows.soonest(series)
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Upcoming")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if upcoming.isEmpty {
          Text("Nothing recurring yet")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          VStack(spacing: NomiSpacing.xs) {
            ForEach(upcoming) { item in
              row(for: item)
            }
          }
        }
      }
    }
  }

  private func row(for item: RecurringSeries) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.label)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
          .lineLimit(1)
        Text(NomiFormatters.relativeTime.localizedString(for: item.nextExpected, relativeTo: Date()))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer(minLength: NomiSpacing.xs)
      Text(NomiFormatters.amountString(minor: item.amountMinor))
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
        .foregroundStyle(NomiColor.debitText)
    }
  }
}

#Preview("Upcoming — default, dark") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Upcoming — empty, dark") {
  UpcomingCard(series: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Upcoming — accessibility 3, dark") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
