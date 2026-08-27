import SwiftUI

/// Card 5: how many rows are waiting on the user — merged, flagged, or
/// unidentified-account transactions (`InsightsStore.reviewQueue`'s own
/// definition), summarized as counts rather than the queue itself, which is a
/// different screen's job.
public struct NeedsYouCard: View {
  public let needsReviewCount: Int
  public let uncategorizedCount: Int

  public init(needsReviewCount: Int, uncategorizedCount: Int) {
    self.needsReviewCount = needsReviewCount
    self.uncategorizedCount = uncategorizedCount
  }

  private var isCaughtUp: Bool {
    needsReviewCount == 0 && uncategorizedCount == 0
  }

  public var body: some View {
    DashboardCard {
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

#Preview("Needs you — accessibility 3, dark") {
  NeedsYouCard(needsReviewCount: 4, uncategorizedCount: 2)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
