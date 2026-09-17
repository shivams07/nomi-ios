import NomiCore
import NomiPreview
import SwiftUI

/// M5 (`nomi-ui-refresh` v5 §Subscriptions). Pushed onto Home's own
/// `NavigationStack` from the Upcoming card — not a fifth tab (design doc
/// §Why not the alternatives). `ui-root-wiring` (M6) is what actually wires
/// `.navigationDestination(for: DashboardRoute.self)` to construct this.
///
/// Reads through `DashboardWiring.recurringSeries(from:)` rather than a
/// second `do`/`catch` of its own — that wiring is internal to `NomiUI` and
/// this screen lives in the same module, so no edit to `DashboardView.swift`
/// is needed to share it.
public struct SubscriptionsScreen: View {
  public let recurringStore: any RecurringInsightsStore

  @State private var now = Date()
  @State private var retryToken = 0

  public init(recurringStore: any RecurringInsightsStore) {
    self.recurringStore = recurringStore
  }

  private var series: DashboardWiring.Load<[RecurringSeries]> {
    DashboardWiring.recurringSeries(from: recurringStore)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.sectionGap) {
        switch series {
        case .loaded(let items) where items.isEmpty:
          emptyState
        case .loaded(let items):
          header(for: items)
          rows(for: items)
        case .failed:
          FailedLoadCaption { retryToken += 1 }
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Subscriptions")
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("Nothing recurring yet")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("Nomi lists a charge here once the same amount has hit your account three months running.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  private func header(for items: [RecurringSeries]) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("\(NomiFormatters.amountString(minor: SubscriptionsSummary.monthlyTotalMinor(items))) a month")
        .nomiTextStyle(.displayValue)
        .foregroundStyle(NomiColor.textPrimary)
      Text(headerCaption(for: items))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  /// "3 subscriptions · next: Netflix in 3 days" — reuses
  /// `SubscriptionRowText.nextCharge`'s own day math rather than a second,
  /// untested copy of it; the leading "next " is dropped from that string
  /// since this caption already supplies its own "next:" label.
  private func headerCaption(for items: [RecurringSeries]) -> String {
    guard let next = SubscriptionsSummary.next(items) else { return "" }
    let plural = items.count == 1 ? "subscription" : "subscriptions"
    let charge = SubscriptionRowText.nextCharge(nextExpected: next.nextExpected, now: now)
    let phrase = charge.hasPrefix("next ") ? String(charge.dropFirst("next ".count)) : charge
    return "\(items.count) \(plural) · next: \(next.label) \(phrase)"
  }

  private func rows(for items: [RecurringSeries]) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      ForEach(SubscriptionsGrouping.byExpectedDay(items)) { group in
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          Text(NomiFormatters.dayMonthAdaptive(group.day, relativeTo: now))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textSecondary)
          VStack(spacing: NomiSpacing.xs) {
            ForEach(group.rows) { item in
              row(for: item)
            }
          }
        }
      }
    }
  }

  private func row(for item: RecurringSeries) -> some View {
    let isOverdue = Calendar.current.startOfDay(for: item.nextExpected) < Calendar.current.startOfDay(for: now)
    return HStack(spacing: NomiSpacing.sm) {
      badge(for: item)
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(item.label)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
          .lineLimit(1)
        HStack(spacing: NomiSpacing.xxs) {
          cadenceCapsule
          if isOverdue {
            Text(SubscriptionRowText.nextCharge(nextExpected: item.nextExpected, now: now))
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
        }
      }
      Spacer(minLength: NomiSpacing.xs)
      Text(NomiFormatters.amountString(minor: item.amountMinor))
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
        .foregroundStyle(NomiColor.debitText)
    }
    .padding(NomiSpacing.cardPadding)
    .background(NomiColor.surfaceRow)
    .nomiCornerRadius(NomiRadius.inset)
  }

  private var cadenceCapsule: some View {
    Text(SubscriptionRowText.cadence)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.glassFill)
      .clipShape(Capsule(style: .continuous))
  }

  /// 40pt — subscription rows and budget tiles' size per `NomiCategoryBadge`'s
  /// own doc comment. No account badge: `RecurringSeries` carries no account
  /// (design doc §Subscriptions, explicit).
  @ViewBuilder
  private func badge(for item: RecurringSeries) -> some View {
    switch SubscriptionBadge.resolve(item) {
    case .category(let category):
      NomiCategoryBadge(symbolName: category.symbolName, paletteSlot: category.paletteSlot, size: 40)
    case .monogram(let letter):
      Circle()
        .fill(NomiColor.glassFill)
        .frame(width: 40, height: 40)
        .overlay(
          Text(letter)
            .nomiTextStyle(.body)
            .foregroundStyle(Color.white)
        )
    }
  }
}

/// Its own private ten lines, same as `DashboardView`'s: that type is
/// private to `DashboardView.swift`, which is M2's file, not this unit's.
private struct FailedLoadCaption: View {
  let retry: () -> Void

  var body: some View {
    Button(action: retry) {
      Text("Couldn't load — tap to retry")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.overBudget)
    }
  }
}

#Preview("Subscriptions — populated, two badges one monogram, dark") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore())
  }
  .preferredColorScheme(.dark)
}

#Preview("Subscriptions — empty, dark") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore(series: []))
  }
  .preferredColorScheme(.dark)
}

private struct SubscriptionsScreenPreviewFailure: Error {}

#Preview("Subscriptions — failed to load, dark") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore(series: [], failure: SubscriptionsScreenPreviewFailure()))
  }
  .preferredColorScheme(.dark)
}

#Preview("Subscriptions — accessibility 3, dark") {
  NavigationStack {
    SubscriptionsScreen(recurringStore: FakeRecurringStore())
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
