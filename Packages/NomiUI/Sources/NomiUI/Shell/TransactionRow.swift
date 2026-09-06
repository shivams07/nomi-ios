import NomiCore
import NomiPreview
import SwiftUI

/// A single ledger row. **Never carries `NomiGlow`** — it lives inside a
/// scrolling list, which is exactly the container that modifier must not enter.
public struct TransactionRow: View {
  public let transaction: NomiCore.Transaction
  public let categoryName: String?
  public let accountName: String?
  public let categorySymbolName: String?
  public let categoryPaletteSlot: Int?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    transaction: NomiCore.Transaction,
    categoryName: String?,
    accountName: String?,
    categorySymbolName: String? = nil,
    categoryPaletteSlot: Int? = nil
  ) {
    self.transaction = transaction
    self.categoryName = categoryName
    self.accountName = accountName
    self.categorySymbolName = categorySymbolName
    self.categoryPaletteSlot = categoryPaletteSlot
  }

  private var isCredit: Bool {
    transaction.direction == .credit
  }

  private var amountText: String {
    Self.amountText(minor: transaction.amountMinor, direction: transaction.direction, currencyCode: transaction.currencyCode)
  }

  private var subtitle: String {
    Self.subtitle(categoryName: categoryName, accountName: accountName, vpa: transaction.counterpartyVPA)
  }

  /// M6: a P2P/Merchant capsule from `upiKindRaw` — short labels for a
  /// row-width capsule, not `UPIDisplay.kindLabel`'s full words
  /// (`TransactionDetailLogic`'s "Person"/"Merchant" for the detail screen's
  /// prose). `nil` for anything not `"p2p"`/`"p2m"`, including a non-UPI row.
  static func upiKindCapsuleText(for kindRaw: String?) -> String? {
    switch kindRaw {
    case "p2p": return "P2P"
    case "p2m": return "Merchant"
    default: return nil
    }
  }

  private var upiKindCapsuleText: String? {
    Self.upiKindCapsuleText(for: transaction.upiKindRaw)
  }

  /// Pure — no `@Model` access — so it is directly unit-testable. `swift test`
  /// on this package's CI runner cannot construct `@Model` instances
  /// headlessly (see `InMemoryModelContainer`'s note in NomiCore), so display
  /// logic that needs coverage lives here rather than on the `Transaction`-typed properties above.
  /// `vpa` becomes the subtitle's third segment when present — M6.
  static func subtitle(categoryName: String?, accountName: String?, vpa: String? = nil) -> String {
    var segments = [categoryName ?? "Uncategorized", accountName ?? "Unassigned"]
    if let vpa, !vpa.isEmpty { segments.append(vpa) }
    return segments.joined(separator: " · ")
  }

  /// Pure — see `subtitle(categoryName:accountName:vpa:)`. `currencyCode`
  /// trails the amount when it is not `"INR"` — pre-positioned for U18
  /// (foreign-currency flagging); every row is INR on `main` today, so
  /// nothing visible changes yet. `NomiFormatters.amountString` always
  /// renders `₹` regardless of code — that mismatch is U18's to fix, not
  /// this unit's.
  static func amountText(minor: Int, direction: Direction, currencyCode: String = "INR") -> String {
    let sign = direction == .credit ? "+" : ""
    let amount = sign + NomiFormatters.amountString(minor: minor)
    return currencyCode == "INR" ? amount : "\(amount) \(currencyCode)"
  }

  public var body: some View {
    // At accessibility Dynamic Type sizes the amount moves below the merchant
    // line rather than fighting it for horizontal space — the AC requires
    // both to survive to .accessibility3 with no truncation.
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          HStack(alignment: .top, spacing: NomiSpacing.sm) {
            iconTile
            header
          }
          amountView
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(alignment: .top, spacing: NomiSpacing.sm) {
          iconTile
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
        if let upiKindCapsuleText {
          upiKindCapsule(text: upiKindCapsuleText)
        }
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

  private var iconTint: Color {
    categoryPaletteSlot.map(paletteSlot) ?? CategoryPalette.other
  }

  private var iconTile: some View {
    Image(systemName: categorySymbolName ?? "questionmark")
      .font(.system(size: 14))
      .foregroundStyle(iconTint)
      .frame(width: 32, height: 32)
      .background(iconTint.opacity(0.16))
      .nomiCornerRadius(NomiRadius.tile)
  }

  /// Same capsule shape as `mergeFlag` — glass fill, no new token.
  private func upiKindCapsule(text: String) -> some View {
    Text(text)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.glassFill)
      .clipShape(Capsule(style: .continuous))
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
    accountName: "HDFC •• 4471",
    categorySymbolName: "fork.knife",
    categoryPaletteSlot: 0
  )
  .padding()
  .background(NomiColor.surfaceRow)
  .preferredColorScheme(.dark)
}

#Preview("Uncategorized-only") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.needsReview }!,
    categoryName: nil,
    accountName: nil
  )
  .padding()
  .background(NomiColor.surfaceRow)
  .preferredColorScheme(.dark)
}

#Preview("Merged row — flag and both sources") {
  let merged = PreviewData.transactions.first { $0.mergedCount > 1 }!
  VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
    TransactionRow(
      transaction: merged,
      categoryName: "Food & Dining",
      accountName: "HDFC •• 4471",
      categorySymbolName: "fork.knife",
      categoryPaletteSlot: 0
    )
    Text(merged.sourceRefs.map { $0.source.rawValue }.joined(separator: " + "))
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
  }
  .padding()
  .background(NomiColor.surfaceRow)
  .preferredColorScheme(.dark)
}

/// `PreviewData.transactions`' main seed rows already carry `upiKindRaw:
/// "p2m"` and a `counterpartyVPA` — no merchant fixture needed. There is no
/// `"p2p"` row in the seed, so this file adds the one M6 needs.
private enum TransactionRowUPIFixtures {
  static let p2p: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -2 * 86400)
    let description = "UPI/P2A/412345678901/RAHUL SHARMA"
    let normalized = normalizeDescription(description)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
      date: date,
      descriptionText: description,
      merchantName: nil,
      upiKindRaw: "p2p",
      counterpartyVPA: "rahul.sharma@okaxis",
      normalizedDescription: normalized,
      amountMinor: 150_00,
      directionRaw: Direction.debit.rawValue,
      sourceRaw: IngestSource.email.rawValue,
      dedupeKey: makeDedupeKey(
        date: date, amountMinor: 150_00, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
      ),
      createdAt: date,
      updatedAt: date
    )
  }()
}

#Preview("UPI — P2P row, dark") {
  TransactionRow(
    transaction: TransactionRowUPIFixtures.p2p,
    categoryName: nil,
    accountName: "HDFC •• 4471"
  )
  .padding()
  .background(NomiColor.surfaceRow)
  .preferredColorScheme(.dark)
}

#Preview("UPI — merchant row, dark") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.mergedCount == 1 && !$0.needsReview }!,
    categoryName: "Food & Dining",
    accountName: "HDFC •• 4471",
    categorySymbolName: "fork.knife",
    categoryPaletteSlot: 0
  )
  .padding()
  .background(NomiColor.surfaceRow)
  .preferredColorScheme(.dark)
}

#Preview("Accessibility 3") {
  TransactionRow(
    transaction: PreviewData.transactions.first!,
    categoryName: "Food & Dining",
    accountName: "HDFC •• 4471",
    categorySymbolName: "fork.knife",
    categoryPaletteSlot: 0
  )
  .padding()
  .background(NomiColor.surfaceRow)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
