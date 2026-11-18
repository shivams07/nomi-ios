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
  /// S1b step 5: Home shows at most two series. The Plan tab has the rest.
  static let limit = 2

  static func soonest(_ series: [RecurringSeries]) -> [RecurringSeries] {
    Array(series.sorted { $0.nextExpected < $1.nextExpected }.prefix(limit))
  }

  /// "Due 12 Nov · monthly", the row's second line. The verb and the line come
  /// from S7's `RecurringCopy`, the same rule the Plan tab's rows use, so Home
  /// and Plan read alike. A series with no category reads "Next".
  static func subtitle(for series: RecurringSeries) -> String {
    RecurringCopy.subtitle(
      verb: RecurringCopy.verb(categoryName: series.category?.name),
      nextExpected: series.nextExpected,
      calendar: NomiCalendar.india
    )
  }
}

/// U17b. Reads `RecurringInsightsStore` (U17a) through `DashboardView`, which
/// resolves it to a `Load<[RecurringSeries]>?` — `nil` when there is no
/// store at all (this card is absent then, never constructed; see
/// `DashboardView`'s `recurringStore`), so every value this type receives
/// already came from a successful read.
///
/// S1b step 5: two rows, each a label, "<verb> <d MMM> · monthly" and the amount.
/// The verb is S7's `RecurringCopy.verb` (X1), the same one Plan uses.
/// "See all" opens the Plan tab through `onSeeAll`. Every row is a debit by
/// construction (`RecurrenceDetector` only ever groups debits), so the amount
/// takes the default ink.
public struct UpcomingCard: View {
  public let series: [RecurringSeries]
  /// Opens the Plan tab (`nomiShowPlan`). `nil` hides "See all".
  public let onSeeAll: (() -> Void)?

  public init(series: [RecurringSeries], onSeeAll: (() -> Void)? = nil) {
    self.series = series
    self.onSeeAll = onSeeAll
  }

  private var upcoming: [RecurringSeries] {
    UpcomingRows.soonest(series)
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        header
        if upcoming.isEmpty {
          Text("Nothing recurring yet")
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
        } else {
          VStack(alignment: .leading, spacing: NomiSpacing.xs) {
            ForEach(upcoming) { item in
              row(for: item)
            }
          }
        }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      Text("Coming up", bundle: .module)
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NomiSpacing.xs)
      if let onSeeAll {
        Button(action: onSeeAll) {
          Text("See all", bundle: .module)
            .nomiTextStyle(.chip)
            .foregroundStyle(NomiColor.navy)
            .frame(minWidth: NomiSpacing.minTarget, minHeight: NomiSpacing.minTarget, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func row(for item: RecurringSeries) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.label)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        Text(UpcomingRows.subtitle(for: item))
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      NomiAmountText(minor: item.amountMinor, style: .amount)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview("Upcoming · default") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries, onSeeAll: {})
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Upcoming · empty") {
  UpcomingCard(series: [], onSeeAll: {})
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Upcoming · accessibility 3") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries, onSeeAll: {})
    .padding()
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
