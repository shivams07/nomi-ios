import NomiCore
import NomiPreview
import SwiftUI

/// A single ledger row. It lives inside a scrolling list, which is exactly the
/// container a decorative effect such as a glow must stay out of.
///
/// One VoiceOver element per row. The label carries the direction word
/// ("debit" or "credit") and the unsigned amount, so the sign glyph is never
/// read as "minus" (DEC-03, A-03.3).
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

  private var subtitle: String {
    Self.subtitle(categoryName: categoryName, accountName: accountName, vpa: transaction.counterpartyVPA)
  }

  private var displayTitle: String {
    Self.title(merchantName: transaction.merchantName, descriptionText: transaction.descriptionText, categoryName: categoryName)
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

  /// Pure — no `@Model` access — so it is directly unit-testable with no
  /// container. Not because none can be built; one can, under XCTest (see
  /// `InMemoryModelContainer`'s measured note in NomiCore). Display
  /// logic that needs coverage lives here rather than on the `Transaction`-typed properties above.
  /// `vpa` becomes the subtitle's third segment when present — M6.
  static func subtitle(categoryName: String?, accountName: String?, vpa: String? = nil) -> String {
    var segments = [categoryName ?? "Uncategorized", accountName ?? "Unassigned"]
    if let vpa, !vpa.isEmpty { segments.append(vpa) }
    return segments.joined(separator: " · ")
  }

  /// The amount's ink token for a direction (DEC-03): a debit is `ink`, a
  /// credit is `inkDeep`. Pure, so a test pins the mapping, and a swapped
  /// mutant fails it.
  static func amountInk(for direction: Direction) -> AmountInk {
    direction == .credit ? .inkDeep : .ink
  }

  /// The two amount inks, kept apart from `Color` so the mapping can be tested.
  enum AmountInk: Equatable {
    case ink
    case inkDeep

    var color: Color {
      switch self {
      case .ink: return NomiColor.ink
      case .inkDeep: return NomiColor.inkDeep
      }
    }
  }

  /// Pure. The row's amount, split for typesetting (DEC-03). A debit is
  /// negated before formatting, so "−" always prints. A credit is positive
  /// and carries "+". Zero carries neither. Currency comes through
  /// `NomiFormatters.amountString`, so a USD row reads "$12.99", never
  /// "₹12.99 USD".
  static func amountParts(minor: Int, direction: Direction, currencyCode: String = "INR") -> NomiAmountParts {
    let magnitude = abs(minor)
    return NomiAmountFormat.parts(
      minor: direction == .credit ? magnitude : -magnitude,
      currencyCode: currencyCode,
      showPlus: direction == .credit
    )
  }

  /// Pure — see `subtitle(categoryName:accountName:vpa:)`. Fallback order for
  /// a row's title: merchant, then a non-blank description, then the
  /// category name, then "Manual entry" — the same fallback order W1-13
  /// (parallel unit) gives `topMerchants`'s label for a blank description.
  static func title(merchantName: String?, descriptionText: String, categoryName: String?) -> String {
    if let merchantName, !merchantName.isEmpty { return merchantName }
    if !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return descriptionText }
    if let categoryName, !categoryName.isEmpty { return categoryName }
    return "Manual entry"
  }

  /// Pure. Two letters for an uncategorized row's badge: the first letter of
  /// each of the first two words, or the first two letters of a single word
  /// ("Amazon" gives "AM"). Upper-cased.
  static func initials(for title: String) -> String {
    let words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let letters: String
    if words.count >= 2 {
      letters = String(words[0].prefix(1)) + String(words[1].prefix(1))
    } else {
      letters = String((words.first ?? "").prefix(2))
    }
    return letters.uppercased()
  }

  /// Pure. The "Transfer" tag (DEC-05, T3). It is words, not colour, so the
  /// state reads without seeing the tag. `nil` when the row is not a transfer.
  /// It reads `isTransfer` only (Amendment 3, U6).
  static func transferTagText(isTransfer: Bool) -> String? {
    isTransfer ? "Transfer" : nil
  }

  /// Pure. The row's single VoiceOver label. It carries the direction word and
  /// the unsigned amount, then "Transfer" for a transfer leg, the UPI kind, a
  /// merge count and "Needs review" when they apply. `mergedSourceCount` is nil
  /// for a row with one source.
  static func accessibilityLabel(
    title: String,
    subtitle: String,
    direction: Direction,
    minor: Int,
    currencyCode: String = "INR",
    isTransfer: Bool,
    upiKind: String?,
    needsReview: Bool,
    mergedSourceCount: Int?
  ) -> String {
    var parts = [
      title,
      subtitle,
      direction == .credit ? "credit" : "debit",
      NomiFormatters.amountString(minor: abs(minor), currencyCode: currencyCode),
    ]
    if let transferTag = transferTagText(isTransfer: isTransfer) { parts.append(transferTag) }
    if let upiKind { parts.append(upiKind) }
    if let mergedSourceCount { parts.append("Merged from \(mergedSourceCount) sources") }
    if needsReview { parts.append("Needs review") }
    return parts.joined(separator: ", ")
  }

  public var body: some View {
    // At accessibility Dynamic Type sizes the amount moves below the merchant
    // line rather than fighting it for horizontal space — the AC requires
    // both to survive to .accessibility3 with no truncation.
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          HStack(alignment: .center, spacing: NomiSpacing.sm) {
            iconTile
            header
          }
          amountView
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(alignment: .center, spacing: NomiSpacing.sm) {
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Self.accessibilityLabel(
        title: displayTitle,
        subtitle: subtitle,
        direction: transaction.direction,
        minor: transaction.amountMinor,
        currencyCode: transaction.currencyCode,
        isTransfer: transaction.isTransfer,
        upiKind: upiKindCapsuleText,
        needsReview: transaction.needsReview,
        mergedSourceCount: transaction.mergedCount > 1 ? transaction.sourceRefs.count : nil
      )
    )
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(spacing: NomiSpacing.xxs) {
        Text(displayTitle)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let tagText = Self.transferTagText(isTransfer: transaction.isTransfer) {
          transferCapsule(text: tagText)
        }
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
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The amount in one line, typeset like `NomiAmountText` (sign, integer,
  /// dimmed decimals) but in the direction's colour: a debit is `ink`, a
  /// credit is `inkDeep` at SemiBold. `NomiAmountText` paints `ink` for every
  /// amount and has no colour parameter, so the split is done here.
  private var amountView: some View {
    let parts = Self.amountParts(
      minor: transaction.amountMinor, direction: transaction.direction, currencyCode: transaction.currencyCode)
    let style: NomiTextStyle = isCredit ? .amountStrong : .amount
    let color = Self.amountInk(for: transaction.direction).color
    return (Text(parts.sign + parts.integer)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(color)
      + Text(parts.decimals)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(color.opacity(NomiColor.decimalOpacityGround)))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Sized to the widest realistic amount, not a sample row, at the credit
  /// weight (SemiBold), the wider of the two.
  private var amountColumnWidth: CGFloat {
    let font = TabularFigures.platformFont(name: NomiFont.interSemiBold, size: 16)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let size = (NomiFormatters.widestRealisticAmount as NSString).size(withAttributes: attributes)
    return size.width
  }

  /// The category's tinted tile (`.neutral`, 40 pt). An uncategorized row has
  /// no category to show, so it gets its initials on `secondaryFill` instead.
  @ViewBuilder
  private var iconTile: some View {
    if categoryName == nil {
      Text(Self.initials(for: displayTitle))
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(width: 40, height: 40)
        .background(Circle().fill(NomiColor.secondaryFill))
        .accessibilityHidden(true)
    } else {
      NomiCategoryBadge(
        symbolName: categorySymbolName ?? "questionmark",
        paletteSlot: categoryPaletteSlot,
        size: 40,
        style: .neutral
      )
    }
  }

  /// The "Transfer" tag: the same capsule as the UPI kind, secondary fill and
  /// caption type, so it adds no token (DEC-05 T3).
  private func transferCapsule(text: String) -> some View {
    Text(text)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.secondaryFill)
      .clipShape(Capsule(style: .continuous))
  }

  /// Same capsule shape as `mergeFlag` — secondary fill, no new token.
  private func upiKindCapsule(text: String) -> some View {
    Text(text)
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.secondaryFill)
      .clipShape(Capsule(style: .continuous))
  }

  private var mergeFlag: some View {
    Text("\(transaction.mergedCount)")
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .padding(.horizontal, NomiSpacing.xxs)
      .background(NomiColor.secondaryFill)
      .clipShape(Capsule(style: .continuous))
      .accessibilityHidden(true)
  }

  private var reviewFlag: some View {
    Circle()
      .fill(CategoryPalette.other)
      .frame(width: 6, height: 6)
      .accessibilityHidden(true)
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
  .background(NomiColor.card)
  .preferredColorScheme(.light)
}

#Preview("Uncategorized-only") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.needsReview }!,
    categoryName: nil,
    accountName: nil
  )
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
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
      .foregroundStyle(NomiColor.inkSecondary)
  }
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
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

#Preview("UPI — P2P row") {
  TransactionRow(
    transaction: TransactionRowUPIFixtures.p2p,
    categoryName: nil,
    accountName: "HDFC •• 4471"
  )
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
}

/// U18/M4 fixtures — a non-INR row for the currency formatter and a blank
/// merchant/description/category row for the title fallback's terminal case.
/// Neither exists in `PreviewData.transactions`, same convention as
/// `TransactionRowUPIFixtures` above.
private enum TransactionRowCurrencyFixtures {
  static let usd: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -4 * 86400)
    let description = "AMAZON.COM AMZN.COM/BILL WA"
    let normalized = normalizeDescription(description)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
      date: date,
      descriptionText: description,
      merchantName: "Amazon",
      normalizedDescription: normalized,
      amountMinor: 1299,
      currencyCode: "USD",
      directionRaw: Direction.debit.rawValue,
      sourceRaw: IngestSource.email.rawValue,
      dedupeKey: makeDedupeKey(
        date: date, amountMinor: 1299, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
      ),
      createdAt: date,
      updatedAt: date
    )
  }()

  static let blankTitleManual: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -5 * 86400)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
      date: date,
      descriptionText: "",
      amountMinor: 500_00,
      directionRaw: Direction.debit.rawValue,
      sourceRaw: IngestSource.manual.rawValue,
      dedupeKey: "manual-blank-title-preview",
      createdAt: date,
      updatedAt: date
    )
  }()
}

#Preview("USD row") {
  TransactionRow(
    transaction: TransactionRowCurrencyFixtures.usd,
    categoryName: "Shopping",
    accountName: "HDFC •• 4471",
    categorySymbolName: "cart",
    categoryPaletteSlot: 1
  )
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
}

#Preview("Blank-title manual row") {
  TransactionRow(
    transaction: TransactionRowCurrencyFixtures.blankTitleManual,
    categoryName: nil,
    accountName: nil
  )
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
}

#Preview("Merchant row") {
  TransactionRow(
    transaction: PreviewData.transactions.first { $0.mergedCount == 1 && !$0.needsReview }!,
    categoryName: "Food & Dining",
    accountName: "HDFC •• 4471",
    categorySymbolName: "fork.knife",
    categoryPaletteSlot: 0
  )
  .padding()
  .background(NomiColor.card)
  .preferredColorScheme(.light)
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
  .background(NomiColor.card)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
