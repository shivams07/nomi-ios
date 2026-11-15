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

  /// Canvas `.li`: a 42 pt leading tile, 12 pt gap, rows at least 64 pt high
  /// with 10 pt of vertical padding.
  private static let tileSize: CGFloat = 42
  private static let rowGap: CGFloat = 12
  private static let rowVerticalPadding: CGFloat = 10
  private static let rowMinHeight: CGFloat = 64

  /// Canvas `.li .t`: SemiBold 15 for the merchant or description line.
  private static let titleFont: Font = .custom(NomiFont.interSemiBold, size: 15, relativeTo: .body)

  private var subtitle: String {
    if isUnparseable {
      return Self.unparseableSubtitle(accountName: accountName)
    }
    return Self.subtitle(
      categoryName: categoryName,
      accountName: accountName,
      vpa: transaction.counterpartyVPA,
      isTransfer: transaction.isTransfer
    )
  }

  private var isUnparseable: Bool {
    Self.showsReviewTag(reason: transaction.needsReviewReason)
  }

  private var displayTitle: String {
    Self.title(
      merchantName: transaction.merchantName,
      descriptionText: transaction.descriptionText,
      categoryName: categoryName,
      unparseable: isUnparseable
    )
  }

  /// M6: the short UPI label that the accessibility label speaks — not
  /// `UPIDisplay.kindLabel`'s full words (`TransactionDetailLogic`'s
  /// "Person"/"Merchant" for the detail screen's prose). The visible capsule
  /// is gone (the subtitle carries the account). `nil` for anything not
  /// `"p2p"`/`"p2m"`, including a non-UPI row.
  static func upiKindLabel(for kindRaw: String?) -> String? {
    switch kindRaw {
    case "p2p": return "P2P"
    case "p2m": return "Merchant"
    default: return nil
    }
  }

  /// Pure — no `@Model` access — so it is directly unit-testable with no
  /// container. Not because none can be built; one can, under XCTest (see
  /// `InMemoryModelContainer`'s measured note in NomiCore). Display
  /// logic that needs coverage lives here rather than on the `Transaction`-typed properties above.
  ///
  /// Always two segments (R2 of the F2b block): the category part, then the
  /// account part, so an unassigned row is never silent. The category part is
  /// "Transfer" for a transfer leg, "Needs a category" when there is no
  /// category, else the category name. The account part is the account name,
  /// or "Unassigned" when it is nil or blank. `vpa` becomes a third segment
  /// when present (M6).
  static func subtitle(
    categoryName: String?,
    accountName: String?,
    vpa: String? = nil,
    isTransfer: Bool = false
  ) -> String {
    let category: String
    if isTransfer {
      category = String(localized: "Transfer", bundle: .module)
    } else if let categoryName, !categoryName.isEmpty {
      category = categoryName
    } else {
      category = String(localized: "Needs a category", bundle: .module)
    }
    var segments = [category, accountPart(accountName)]
    if let vpa, !vpa.isEmpty { segments.append(vpa) }
    return segments.joined(separator: " · ")
  }

  /// The account segment of a row's subtitle: the name, or "Unassigned".
  static func accountPart(_ accountName: String?) -> String {
    guard let accountName, !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return String(localized: "Unassigned", bundle: .module)
    }
    return accountName
  }

  /// Pure. The subtitle of an unparseable row (Activity board): the account
  /// part, then "tap to fix or dismiss".
  static func unparseableSubtitle(accountName: String?) -> String {
    "\(accountPart(accountName)) · \(String(localized: "tap to fix or dismiss", bundle: .module))"
  }

  /// Pure. An unparseable row shows the Review tag in place of its amount, so
  /// no amount is shown for a row where nothing was read.
  static func showsReviewTag(reason: NeedsReviewReason?) -> Bool {
    reason == .unparseable
  }

  /// The amount's ink token for a direction (DEC-03 as amended by R1 of the
  /// F2b block): a debit is `ink`, a credit is `navy`, a transfer leg is
  /// `inkSecondary` and unsigned. Pure, so a test pins the mapping, and a
  /// swapped mutant fails it.
  static func amountInk(for direction: Direction, isTransfer: Bool = false) -> AmountInk {
    if isTransfer { return .inkSecondary }
    return direction == .credit ? .navy : .ink
  }

  /// The three amount inks, kept apart from `Color` so the mapping can be tested.
  enum AmountInk: Equatable {
    case ink
    case navy
    case inkSecondary

    var color: Color {
      switch self {
      case .ink: return NomiColor.ink
      case .navy: return NomiColor.navy
      case .inkSecondary: return NomiColor.inkSecondary
      }
    }
  }

  /// Pure. The row's amount, split for typesetting (DEC-03). A debit is
  /// negated before formatting, so "−" always prints. A credit is positive
  /// and carries "+". A transfer leg is unsigned: it moves money between the
  /// user's own accounts, so neither sign applies. Zero carries no sign.
  /// Currency comes through `NomiFormatters.amountString`, so a USD row reads
  /// "$12.99", never "₹12.99 USD".
  static func amountParts(
    minor: Int,
    direction: Direction,
    currencyCode: String = "INR",
    isTransfer: Bool = false
  ) -> NomiAmountParts {
    let magnitude = abs(minor)
    if isTransfer {
      return NomiAmountFormat.parts(minor: magnitude, currencyCode: currencyCode, showPlus: false)
    }
    return NomiAmountFormat.parts(
      minor: direction == .credit ? magnitude : -magnitude,
      currencyCode: currencyCode,
      showPlus: direction == .credit
    )
  }

  /// Pure — see `subtitle(categoryName:accountName:vpa:isTransfer:)`. Fallback order for
  /// a row's title: merchant, then a non-blank description, then the
  /// category name, then "Manual entry" — the same fallback order W1-13
  /// (parallel unit) gives `topMerchants`'s label for a blank description.
  /// An unparseable row has no readable title, so it reads "Couldn't read this alert".
  static func title(
    merchantName: String?,
    descriptionText: String,
    categoryName: String?,
    unparseable: Bool = false
  ) -> String {
    if unparseable { return String(localized: "Couldn't read this alert", bundle: .module) }
    if let merchantName, !merchantName.isEmpty { return merchantName }
    if !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return descriptionText }
    if let categoryName, !categoryName.isEmpty { return categoryName }
    return "Manual entry"
  }

  /// What the leading tile shows (R3 of the F2b block).
  enum LeadingTile: Equatable {
    /// A neutral category badge with this symbol. Transfer legs get the
    /// transfer arrows; an uncategorised row gets "questionmark", which the
    /// badge draws in the warning tones.
    case badge(symbolName: String)
    /// Two letters on `secondaryFill`, for a categorised row that has no icon.
    case initials
  }

  /// Pure. The leading tile for a row: transfer arrows for a transfer leg, the
  /// amber "?" for an uncategorised row, the category icon in neutral moss for a
  /// categorised row, and initials only when a categorised row has no icon.
  static func leadingTile(categoryName: String?, categorySymbolName: String?, isTransfer: Bool) -> LeadingTile {
    if isTransfer { return .badge(symbolName: "arrow.left.arrow.right") }
    guard let categoryName, !categoryName.isEmpty else { return .badge(symbolName: "questionmark") }
    if let categorySymbolName { return .badge(symbolName: categorySymbolName) }
    return .initials
  }

  /// Pure. Two letters for a row's initials tile: the first letter of
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

  /// Pure. The "Transfer" word (DEC-05, T3). It is words, not colour, so the
  /// state reads without seeing the tile. `nil` when the row is not a transfer.
  /// It reads `isTransfer` only (Amendment 3, U6).
  static func transferTagText(isTransfer: Bool) -> String? {
    isTransfer ? String(localized: "Transfer", bundle: .module) : nil
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
    // line rather than fighting it for horizontal space. Both lines may wrap
    // to two lines there; below AX1 each is one line and never wraps.
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          HStack(alignment: .center, spacing: Self.rowGap) {
            leadingTileView
            header(lineLimit: 2)
          }
          trailing
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        HStack(alignment: .center, spacing: Self.rowGap) {
          leadingTileView
          header(lineLimit: 1)
          Spacer(minLength: NomiSpacing.xs)
          trailing
            .frame(minWidth: amountColumnWidth, alignment: .trailing)
            .layoutPriority(1)
        }
      }
    }
    .padding(.vertical, Self.rowVerticalPadding)
    .frame(minHeight: Self.rowMinHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Self.accessibilityLabel(
        title: displayTitle,
        subtitle: subtitle,
        direction: transaction.direction,
        minor: transaction.amountMinor,
        currencyCode: transaction.currencyCode,
        isTransfer: transaction.isTransfer,
        upiKind: Self.upiKindLabel(for: transaction.upiKindRaw),
        needsReview: transaction.needsReview,
        mergedSourceCount: transaction.mergedCount > 1 ? transaction.sourceRefs.count : nil
      )
    )
  }

  private func header(lineLimit: Int) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(spacing: NomiSpacing.xxs) {
        Text(displayTitle)
          .font(Self.titleFont)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(lineLimit)
          .fixedSize(horizontal: false, vertical: true)
        if transaction.mergedCount > 1 {
          mergeFlag
        }
        if transaction.needsReview && !isUnparseable {
          reviewFlag
        }
      }
      Text(subtitle)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .lineLimit(lineLimit)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The trailing column: the Review tag for an unparseable row, else the amount.
  @ViewBuilder
  private var trailing: some View {
    if isUnparseable {
      NomiTag(String(localized: "Review", bundle: .module), tone: .warning)
    } else {
      amountView
    }
  }

  /// The amount in one line, typeset like `NomiAmountText` (sign, integer,
  /// dimmed decimals) but in the direction's colour: a debit is `ink`, a
  /// credit is `navy`, a transfer is `inkSecondary`, all at SemiBold (`.amount`).
  /// `NomiAmountText` paints `ink` for every amount and has no colour parameter,
  /// so the split is done here.
  private var amountView: some View {
    let parts = Self.amountParts(
      minor: transaction.amountMinor,
      direction: transaction.direction,
      currencyCode: transaction.currencyCode,
      isTransfer: transaction.isTransfer
    )
    let style: NomiTextStyle = .amount
    let color = Self.amountInk(for: transaction.direction, isTransfer: transaction.isTransfer).color
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

  /// Sized to the widest realistic amount, not a sample row, at the amount
  /// weight (SemiBold), so the column does not shift between rows.
  private var amountColumnWidth: CGFloat {
    let font = TabularFigures.platformFont(name: NomiFont.interSemiBold, size: 16)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let size = (NomiFormatters.widestRealisticAmount as NSString).size(withAttributes: attributes)
    return size.width
  }

  /// The leading tile (R3): a neutral badge, the amber "?" for an uncategorised
  /// row, or the initials of a categorised row that has no icon.
  @ViewBuilder
  private var leadingTileView: some View {
    switch Self.leadingTile(
      categoryName: categoryName,
      categorySymbolName: categorySymbolName,
      isTransfer: transaction.isTransfer
    ) {
    case .badge(let symbolName):
      NomiCategoryBadge(
        symbolName: symbolName,
        paletteSlot: categoryPaletteSlot,
        size: Self.tileSize,
        style: .neutral
      )
    case .initials:
      Text(Self.initials(for: displayTitle))
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(Circle().fill(NomiColor.secondaryFill))
        .accessibilityHidden(true)
    }
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
