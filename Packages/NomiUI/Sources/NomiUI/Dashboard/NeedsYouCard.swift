import SwiftUI

/// Card 5 (HM2, Main artboard): how many transactions are waiting on the user,
/// summarised as one count rather than the queue itself, which is a different
/// screen's job. It is a 76 pt card. When both counts are zero it becomes a
/// 44 pt, non-interactive "All caught up" row.
public struct NeedsYouCard: View {
  public let needsReviewCount: Int
  public let uncategorizedCount: Int

  /// M9. `nil` — the default — leaves the card non-interactive: no chevron,
  /// no `Button` wrapper. `DashboardView` supplies this, choosing between its
  /// `onOpenReviewQueue` and `onOpenUncategorized` by the counts above (G1).
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

  private var line: String {
    NeedsYouText.line(needsReviewCount: needsReviewCount, uncategorizedCount: uncategorizedCount)
  }

  public var body: some View {
    if isCaughtUp {
      caughtUpRow
    } else if isTappable, let onTap {
      Button(action: onTap) { card }
        .buttonStyle(.plain)
    } else {
      card
    }
  }

  private var card: some View {
    DashboardCard {
      HStack(alignment: .center, spacing: 12) {
        NomiCategoryBadge(symbolName: "flag", paletteSlot: nil, size: 40, style: .neutral)
        VStack(alignment: .leading, spacing: 2) {
          Text("Needs you")
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.dayHeader)
          Text(line)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if isTappable {
          Image(systemName: "chevron.right")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(NomiColor.inkSecondary)
            .accessibilityHidden(true)
        }
      }
      .frame(minHeight: NomiSpacing.minTarget, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Needs you: \(line)")
    }
  }

  private var caughtUpRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.circle")
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(NomiColor.iconGlyph)
        .accessibilityHidden(true)
      Text("All caught up")
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    .accessibilityElement(children: .combine)
  }
}

/// The Needs-you line. The review count leads, because the Ledger's "Needs
/// review" queue is where the card goes. The uncategorized count is shown only
/// when nothing needs review. Both counts zero is the caught-up row, which
/// never asks for a line.
enum NeedsYouText {
  static func line(needsReviewCount: Int, uncategorizedCount: Int) -> String {
    if needsReviewCount > 0 {
      return "\(needsReviewCount) \(noun(needsReviewCount)) to review"
    }
    return "\(uncategorizedCount) uncategorized \(noun(uncategorizedCount))"
  }

  private static func noun(_ count: Int) -> String {
    count == 1 ? "transaction" : "transactions"
  }
}

#Preview("Needs you · default") {
  NeedsYouCard(needsReviewCount: 2, uncategorizedCount: 0)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Needs you · tappable") {
  NeedsYouCard(needsReviewCount: 2, uncategorizedCount: 1, onTap: {})
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Needs you · all caught up") {
  NeedsYouCard(needsReviewCount: 0, uncategorizedCount: 0)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Needs you · accessibility 3") {
  NeedsYouCard(needsReviewCount: 2, uncategorizedCount: 1, onTap: {})
    .padding()
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
