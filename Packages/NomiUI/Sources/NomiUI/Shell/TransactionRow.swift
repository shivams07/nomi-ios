import NomiCore
import NomiPreview
import SwiftUI

/// A single ledger row. **Never carries `NomiGlow`** — it lives inside a
/// scrolling list, which is exactly the container that modifier must not enter.
public struct TransactionRow: View {
  public let transaction: NomiCore.Transaction
  public let categoryName: String?
  public let accountName: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(transaction: NomiCore.Transaction, categoryName: String?, accountName: String?) {
    self.transaction = transaction
    self.categoryName = categoryName
    self.accountName = accountName
  }

  private var isCredit: Bool {
    transaction.direction == .credit
  }

  private var amountText: String {
    let sign = isCredit ? "+" : ""
    return sign + NomiFormatters.amountString(minor: transaction.amountMinor)
  }

  private var subtitle: String {
    var parts: [String] = []
    parts.append(categoryName ?? "Uncategorized")
    parts.append(accountName ?? "Unassigned")
    return parts.joined(separator: " · ")
  }

  var subtitleForTesting: String { subtitle }
  var amountTextForTesting: String { amountText }

  public var body: some View {
    // At accessibility Dynamic Type sizes the amount moves below the merchant
    // line rather than fighting it for horizontal space — the AC requires
    // both to survive to .accessibility3 with no truncation.
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          header
          amountView
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(alignment: .top, spacing: NomiSpacing.sm) {
          header
          Spacer(minLength: NomiSpacing.xs)
          amountView
            .frame(minWidth: amountColumnWidth, alignment: .trailing)
            .layoutPriority(1)
        }
      }
    }
    .padding(.vertical, NomiSpacing.xs)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(spacing: NomiSpacing.xxs) {
        Text(transaction.merchantName ?? transaction.descriptionText)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        if transaction.mergedCount > 1 {
          mergeFlag
        }
        if transaction.needsReview {
          reviewFlag
        }
      }
      Text(subtitle)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var amountView: some View {
    Text(amountText)
      .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 16))
      .foregroundStyle(isCredit ? NomiColor.creditText : NomiColor.debitText)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Sized to the widest realistic amount, not a sample row — Montserrat is
  /// wider than Inter at the same size, so this column cannot assume v2's width.
  private var amountColumnWidth: CGFloat {
    let font = TabularFigures.platformFont(name: NomiFont.montserratMedium, size: 16)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let size = (NomiFormatters.widestRealisticAmount as NSString).size(withAttributes: attributes)
    return size.width
  }

  private var mergeFlag: some View {
    Text("\(transaction.mergedCount)")
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.glassFill)
      .clipShape(Capsule(style: .continuous))
      .accessibilityLabel("Merged from \(transaction.sourceRefs.count) sources")
  }

  private var reviewFlag: some View {
    Circle()
      .fill(CategoryPalette.other)
      .frame(width: 6, height: 6)
      .accessibilityLabel("Needs review")
  }
}

#Preview("Default") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.mergedCount == 1 && !$0.needsReview }!,
    categoryName: "Food & Dining",
    accountName: "HDFC •• 4471"
  )
  .padding()
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}

#Preview("Uncategorized-only") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.needsReview }!,
    categoryName: nil,
    accountName: nil
  )
  .padding()
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}

#Preview("Merged row — flag and both sources") {
  let merged = PreviewData.transactions.first { $0.mergedCount > 1 }!
  VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
    TransactionRow(transaction: merged, categoryName: "Food & Dining", accountName: "HDFC •• 4471")
    Text(merged.sourceRefs.map { $0.source.rawValue }.joined(separator: " + "))
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
  }
  .padding()
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}

#Preview("Accessibility 3") {
  TransactionRow(
    transaction: PreviewData.transactions.first!,
    categoryName: "Food & Dining",
    accountName: "HDFC •• 4471"
  )
  .padding()
  .background(NomiColor.surfaceRaised)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
