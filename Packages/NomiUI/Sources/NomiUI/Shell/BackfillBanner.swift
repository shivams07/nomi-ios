import NomiCore
import SwiftUI

/// Shown above the content while a mail backfill is in progress: a card with
/// the scan count and a progress capsule. The track is `track` (`#DCE8F5`) and
/// the fill is `navy`, the same pair `NomiProgressBar` uses. Deliberately not
/// `NomiProgressBar` itself: that component's 90% threshold is a budget
/// concept, and a near-complete scan is not "over budget".
public struct BackfillBanner: View {
  public let progress: BackfillProgress

  public init(progress: BackfillProgress) {
    self.progress = progress
  }

  private var fraction: Double {
    guard progress.total > 0 else { return 0 }
    return min(max(Double(progress.scanned) / Double(progress.total), 0), 1)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("Scanning mail — \(progress.created) found")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(NomiColor.track)
          Capsule(style: .continuous)
            .fill(NomiColor.navy)
            .frame(width: proxy.size.width * fraction)
        }
      }
      .frame(height: NomiSpacing.xs)
      .clipShape(Capsule(style: .continuous))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // The bar is one reading for VoiceOver: the caption and the value, not the
    // track's shapes.
    .accessibilityElement(children: .combine)
    .nomiCard(padding: EdgeInsets(
      top: NomiSpacing.cardPadding,
      leading: NomiSpacing.cardPadding,
      bottom: NomiSpacing.cardPadding,
      trailing: NomiSpacing.cardPadding
    ))
  }
}

#Preview("Mid-backfill") {
  BackfillBanner(progress: BackfillProgress(scanned: 340, total: 1200, created: 58))
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
