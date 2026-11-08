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

  /// "Netflix · renews 12 Nov" — the row's name and its renewal day, as the
  /// Main artboard words it.
  static func line(for series: RecurringSeries) -> String {
    "\(series.label) · renews \(NomiFormatters.dayMonth.string(from: series.nextExpected))"
  }
}

/// U17b. Reads `RecurringInsightsStore` (U17a) through `DashboardView`, which
/// resolves it to a `Load<[RecurringSeries]>?` — `nil` when there is no
/// store at all (this card is absent then, never constructed; see
/// `DashboardView`'s `recurringStore`), so every value this type receives
/// already came from a successful read.
///
/// HM2: the Main artboard draws each upcoming series as a plain line with its
/// amount, and no badge. The whole card is a NavigationLink to Subscriptions
/// (`DashboardView`), so the chevron is the affordance.
///
/// Every row is a debit by construction (`RecurrenceDetector` only ever
/// groups debits), and the artboard prints its amount with no sign, so the
/// amount takes the default ink.
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
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        HStack(spacing: NomiSpacing.xs) {
          Text("Upcoming")
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.dayHeader)
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(NomiColor.inkSecondary)
            .accessibilityHidden(true)
        }
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

  private func row(for item: RecurringSeries) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
      Text(UpcomingRows.line(for: item))
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      NomiAmountText(minor: item.amountMinor, style: .amount)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview("Upcoming · default") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Upcoming · empty") {
  UpcomingCard(series: [])
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Upcoming · accessibility 3") {
  UpcomingCard(series: FakeRecurringStore.sampleSeries)
    .padding()
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
