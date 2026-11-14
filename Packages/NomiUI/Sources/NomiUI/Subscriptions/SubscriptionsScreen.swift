import NomiCore
import NomiPreview
import SwiftUI

/// The Subscriptions page (M5; BS, approved `Subscriptions` artboard). Pushed
/// onto Home's own `NavigationStack` from the Upcoming card, not a fifth tab
/// (design doc §Why not the alternatives). Read-only, as shipped: no actions.
///
/// Shape: an H0 large title, a total card (the monthly sum at 32 with "a month",
/// then the count and the next charge), then rows grouped under their day.
///
/// Reads through `DashboardWiring.recurringSeries(from:)` rather than a second
/// `do`/`catch` of its own. That wiring is internal to `NomiUI` and this screen
/// lives in the same module, so no edit to `DashboardView.swift` is needed.
public struct SubscriptionsScreen: View {
  public let recurringStore: any RecurringInsightsStore

  /// G4. The composition root's `InsightsCache` generation. Stored and never
  /// read: a new value from the parent re-renders this screen, which re-reads
  /// the series. Same contract as `DashboardView.refreshToken`.
  public let refreshToken: Int

  @State private var now = Date()
  @State private var retryToken = 0

  public init(recurringStore: any RecurringInsightsStore, refreshToken: Int = 0) {
    self.recurringStore = recurringStore
    self.refreshToken = refreshToken
  }

  private var series: DashboardWiring.Load<[RecurringSeries]> {
    _ = retryToken
    return DashboardWiring.recurringSeries(from: recurringStore)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.md) {
        switch series {
        case .loaded(let items) where items.isEmpty:
          emptyState
        case .loaded(let items):
          header(for: items)
          rows(for: items)
        case .failed:
          NomiLoadFailedCard(message: "Subscriptions didn’t load.") {
            retryToken += 1
          }
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.sm)
    }
    .background(NomiColor.ground)
    .navigationTitle("Subscriptions")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
  }

  private var emptyState: some View {
    NomiEmptyState(
      systemImage: "arrow.triangle.2.circlepath",
      title: "No subscriptions yet",
      message: "Repeating charges Nomi finds in your transactions will appear here."
    )
    .padding(.top, 96)
  }

  private func header(for items: [RecurringSeries]) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        SizedAmountText(
          minor: SubscriptionsSummary.monthlyTotalMinor(items),
          fontName: NomiFont.interRegular,
          size: 32,
          tracking: -0.6
        )
        Text("a month")
          .font(.custom(NomiFont.interRegular, size: 16, relativeTo: .body))
          .foregroundStyle(NomiColor.ink)
      }
      .accessibilityElement(children: .combine)
      Text(headerCaption(for: items))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
  }

  /// "3 subscriptions · next: Netflix in 3 days". Reuses
  /// `SubscriptionRowText.nextCharge`'s own day math rather than a second,
  /// untested copy of it. The leading "next " is dropped from that string,
  /// since this caption already supplies its own "next:" label.
  private func headerCaption(for items: [RecurringSeries]) -> String {
    guard let next = SubscriptionsSummary.next(items) else { return "" }
    let charge = SubscriptionRowText.nextCharge(nextExpected: next.nextExpected, now: now)
    let phrase = charge.hasPrefix("next ") ? String(charge.dropFirst("next ".count)) : charge
    return "\(SubscriptionsSummary.countText(items.count)) · next: \(next.label) \(phrase)"
  }

  private func rows(for items: [RecurringSeries]) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.md) {
      ForEach(SubscriptionsGrouping.byExpectedDay(items)) { group in
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          Text(NomiFormatters.dayMonthAdaptive(group.day, relativeTo: now))
            .nomiTextStyle(.subhead)
            .foregroundStyle(NomiColor.dayHeader)
            .accessibilityAddTraits(.isHeader)
          ForEach(group.rows) { item in
            row(for: item)
          }
        }
      }
    }
  }

  private func row(for item: RecurringSeries) -> some View {
    let isOverdue = Calendar.current.startOfDay(for: item.nextExpected) < Calendar.current.startOfDay(for: now)
    return HStack(spacing: NomiSpacing.cardGap) {
      badge(for: item)
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(item.label)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        HStack(spacing: NomiSpacing.xxs) {
          cadenceCapsule
          if isOverdue {
            Text(SubscriptionRowText.nextCharge(nextExpected: item.nextExpected, now: now))
              .nomiTextStyle(.footnote)
              .foregroundStyle(NomiColor.inkSecondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      SizedAmountText(minor: item.amountMinor, fontName: NomiFont.interMedium, size: 16)
    }
    .accessibilityElement(children: .combine)
    .nomiCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
  }

  private var cadenceCapsule: some View {
    Text(SubscriptionRowText.cadence)
      .nomiTextStyle(.footnote)
      .foregroundStyle(NomiColor.dayHeader)
      .padding(.horizontal, NomiSpacing.xs)
      .padding(.vertical, 2)
      .background(Capsule(style: .continuous).fill(NomiColor.track))
  }

  /// 40 pt, the size `NomiCategoryBadge`'s own doc comment gives subscription
  /// rows. No account badge: `RecurringSeries` carries no account (design doc
  /// §Subscriptions, explicit). A series with no category gets a monogram on
  /// the neutral `track` fill, with no logo fetching of any kind.
  @ViewBuilder
  private func badge(for item: RecurringSeries) -> some View {
    switch SubscriptionBadge.resolve(item) {
    case .category(let category):
      NomiCategoryBadge(symbolName: category.symbolName, paletteSlot: category.paletteSlot, size: 40)
    case .monogram(let letter):
      Circle()
        .fill(NomiColor.track)
        .frame(width: 40, height: 40)
        .overlay(
          Text(letter)
            .font(.custom(NomiFont.interMedium, size: 16, relativeTo: .body))
            .foregroundStyle(NomiColor.inkDeep)
        )
    }
  }
}

/// Manual conformance, as on `DashboardView`: identity for the store, and
/// `refreshToken` compared so a test can assert that a new generation makes a
/// different view value.
extension SubscriptionsScreen: Equatable {
  public static func == (lhs: SubscriptionsScreen, rhs: SubscriptionsScreen) -> Bool {
    lhs.recurringStore === rhs.recurringStore && lhs.refreshToken == rhs.refreshToken
  }
}

#Preview("Subscriptions — populated, two badges one monogram") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore())
  }
  .preferredColorScheme(.light)
}

#Preview("Subscriptions — empty") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore(series: []))
  }
  .preferredColorScheme(.light)
}

private struct SubscriptionsScreenPreviewFailure: Error {}

#Preview("Subscriptions — failed to load") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore(series: [], failure: SubscriptionsScreenPreviewFailure()))
  }
  .preferredColorScheme(.light)
}

#Preview("Subscriptions — accessibility 3") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore())
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
