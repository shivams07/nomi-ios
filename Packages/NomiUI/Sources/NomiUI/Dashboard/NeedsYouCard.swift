import NomiCore
import SwiftUI

/// The counts behind the Review card (S1b step 3). Built from `ReviewQueueLogic.items`,
/// the list the Review queue shows, so the card and the queue agree.
///
/// - `total` is the queue's length, the same as `ReviewQueueLogic.count`.
/// - `uncategorised` is the queue rows with no category, transfers excluded.
/// - `unsure` is the flagged rows that already have a category (a heuristic match
///   the user should check). A row with no category counts once, as uncategorised.
struct ReviewCounts: Equatable {
  let total: Int
  let uncategorised: Int
  let unsure: Int

  init(items: [NomiCore.Transaction]) {
    total = items.count
    uncategorised = items.filter { $0.categoryID == nil && !$0.isTransfer }.count
    unsure = items.filter { $0.needsReview && $0.categoryID != nil }.count
  }

  init(total: Int, uncategorised: Int, unsure: Int) {
    self.total = total
    self.uncategorised = uncategorised
    self.unsure = unsure
  }
}

/// Card 5 of the Home sheet, redrawn for S1b as the artboard's Review card: a dark
/// icon tile, "<n> transactions to review", a caption that names what is in it, and
/// a small "Review" button that opens the queue (`nomiOpenReview`). It is hidden
/// when the queue is empty. The file keeps its name from the earlier Needs-you card.
struct NeedsYouCard: View {
  let counts: ReviewCounts
  /// Opens the Review queue. `nil` hides the button, and the card stays a read.
  let onReview: (() -> Void)?

  var body: some View {
    if counts.total > 0 {
      DashboardCard {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: "checkmark.circle")
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .foregroundStyle(NomiColor.card)
            .frame(width: 40, height: 40)
            .background(Circle().fill(NomiColor.navy))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(ReviewCountsText.title(total: counts.total))
              .nomiTextStyle(.rowTitle)
              .foregroundStyle(NomiColor.ink)
              .fixedSize(horizontal: false, vertical: true)
            if let caption = ReviewCountsText.caption(uncategorised: counts.uncategorised, unsure: counts.unsure) {
              Text(caption)
                .nomiTextStyle(.footnote)
                .foregroundStyle(NomiColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
          if let onReview {
            Button(action: onReview) {
              Text("Review", bundle: .module)
                .padding(.horizontal, NomiSpacing.sm)
            }
            .buttonStyle(NomiPrimaryButtonStyle(height: 36))
            .fixedSize()
          }
        }
        .frame(minHeight: NomiSpacing.minTarget, alignment: .leading)
      }
    }
  }
}

/// The Review card's words. Each count is a catalog plural, so the card reads
/// "1 transaction to review" and "3 uncategorised" correctly.
enum ReviewCountsText {
  static func title(total: Int) -> String {
    String(localized: "\(total) transactions to review", bundle: .module)
  }

  /// "<u> uncategorised · <f> unsure matches", each part left out at zero. `nil`
  /// when both are zero, so the card has no caption line.
  static func caption(uncategorised: Int, unsure: Int) -> String? {
    var parts: [String] = []
    if uncategorised > 0 {
      parts.append(String(localized: "\(uncategorised) uncategorised", bundle: .module))
    }
    if unsure > 0 {
      parts.append(String(localized: "\(unsure) unsure matches", bundle: .module))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// The retired Needs-you line. The Review card replaces it on Home, but the
/// catalog keys stay until X1 (`PluralCopyTests` reads them).
enum NeedsYouText {
  /// Each sentence is one catalog key, so its plural variations are selected
  /// by the count and a translation can reorder the whole line.
  static func line(needsReviewCount: Int, uncategorizedCount: Int) -> String {
    if needsReviewCount > 0 {
      return String(localized: "\(needsReviewCount) transactions to review", bundle: .module)
    }
    return String(localized: "\(uncategorizedCount) uncategorized transactions", bundle: .module)
  }
}

#Preview("Review · two parts") {
  NeedsYouCard(
    counts: ReviewCounts(total: 7, uncategorised: 3, unsure: 4),
    onReview: {}
  )
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
