import SwiftUI

/// Card 5: how many rows are waiting on the user — merged, flagged, or
/// unidentified-account transactions (`InsightsStore.reviewQueue`'s own
/// definition), summarized as counts rather than the queue itself, which is a
/// different screen's job.
public struct NeedsYouCard: View {
  public let needsReviewCount: Int
  public let uncategorizedCount: Int

  /// M9. `nil` — the default — leaves the card non-interactive: no chevron,
  /// no `Button` wrapper, same as before this unit. `DashboardView` supplies
  /// this from its own `onOpenReviewQueue`.
  public let onTap: (() -> Void)?

  public init(needsReviewCount: Int, uncategorizedCount: Int, onTap: (() -> Void)? = nil) {
    self.needsReviewCount = needsReviewCount
    self.uncategorizedCount = uncategorizedCount
    self.onTap = onTap
  }

  private var isCaughtUp: Bool {
    needsReviewCount == 0 && uncategorizedCount == 0
  }

  /// M9: mirrors `DashboardWiring.needsYouIsTappable`, the pure rule that
  /// backs this — "all caught up" has nothing to tap into.
  private var isTappable: Bool {
    onTap != nil && DashboardWiring.needsYouIsTappable(needsReviewCount: needsReviewCount, uncategorizedCount: uncategorizedCount)
  }

  public var body: some View {
    DashboardCard {
      if isTappable, let onTap {
        Button(action: onTap) { content }
          .buttonStyle(.plain)
      } else {
        content
      }
    }
  }

  private var content: some View {
    HStack(alignment: .top, spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text("Needs you")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if isCaughtUp {
          Text("All caught up")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          if needsReviewCount > 0 {
            Text("\(needsReviewCount) to review")
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textSecondary)
          }
          if uncategorizedCount > 0 {
            Text("\(uncategorizedCount) uncategorized")
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textSecondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if isTappable {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
  }
}

#Preview("Needs you — default, dark") {
  NeedsYouCard(needsReviewCount: 4, uncategorizedCount: 2)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Needs you — all caught up, dark") {
  NeedsYouCard(needsReviewCount: 0, uncategorizedCount: 0)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

/// M9 done-when: "counts > 0 with a chevron" — `onTap` non-nil and at least
/// one count positive is exactly `isTappable`.
#Preview("Needs you — tappable, chevron, dark") {
  NeedsYouCard(needsReviewCount: 4, uncategorizedCount: 2, onTap: {})
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Needs you — accessibility 3, dark") {
  NeedsYouCard(needsReviewCount: 4, uncategorizedCount: 2)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
