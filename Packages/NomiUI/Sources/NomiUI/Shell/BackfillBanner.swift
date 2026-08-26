import NomiCore
import SwiftUI

/// Shown above the ledger while a mail backfill is in progress. Uses the same
/// progress-track fill (`#2388FF`) as `NomiProgressBar` — Nomi's one progress
/// track, and this is the other place it goes. Deliberately not
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
          Capsule(style: .continuous).fill(NomiColor.surface)
          Capsule(style: .continuous)
            .fill(NomiColor.progressTrackFill)
            .frame(width: proxy.size.width * fraction)
        }
      }
      .frame(height: NomiSpacing.xs)
      .clipShape(Capsule(style: .continuous))
    }
    .padding(NomiSpacing.cardPadding)
    .background(NomiColor.glassFill)
    .overlay(
      RoundedRectangle(cornerRadius: NomiRadius.card, style: NomiRadius.cardSheetStyle)
        .stroke(NomiColor.glassHairline, lineWidth: 1)
    )
    .nomiCornerRadius(NomiRadius.card)
  }
}

#Preview("Mid-backfill") {
  BackfillBanner(progress: BackfillProgress(scanned: 340, total: 1200, created: 58))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}
