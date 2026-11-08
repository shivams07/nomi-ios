import NomiCore
import NomiPreview
import SwiftUI

/// Anything with a `date` can be ranked by recency. Kept separate from
/// `Transaction` so the sort/limit logic below is testable with no container —
/// not because this package's runner cannot build one, which it can under
/// XCTest (see `InMemoryModelContainer`'s measured note in NomiCore).
/// `Transaction`'s conformance costs nothing extra; it only reads
/// an existing `date` property, never constructs one.
protocol DatedRow {
  var date: Date { get }
}

extension NomiCore.Transaction: DatedRow {}

enum RecentRows {
  static func mostRecent<T: DatedRow>(_ rows: [T], limit: Int) -> [T] {
    Array(rows.sorted { $0.date > $1.date }.prefix(limit))
  }
}

/// `RecentTransactionsCard`'s badge dictionary — `uniquingKeysWith` first
/// wins because duplicate ids exist on two-device stores (the ledger's own
/// guard, mirrored here rather than assumed away).
enum RecentBadges {
  static func lookup(_ categories: [CategoryBadge]) -> [UUID: CategoryBadge] {
    Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }
}

/// The text and the signed figure of one Recent row, pure so the tests can
/// reach them.
enum RecentRowText {
  /// Merchant, then a non-blank description, then the category, then "Manual
  /// entry". The same order `TransactionRow.title` uses.
  static func title(merchantName: String?, descriptionText: String, categoryName: String?) -> String {
    if let merchantName, !merchantName.isEmpty { return merchantName }
    if !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return descriptionText }
    if let categoryName, !categoryName.isEmpty { return categoryName }
    return "Manual entry"
  }

  /// The category, or "Uncategorized". The account name is not on this card's
  /// init, so it is not shown here.
  static func subtitle(categoryName: String?) -> String {
    categoryName ?? "Uncategorized"
  }

  /// DEC-03 and A-03: a debit is built from a negative minor, so its "−" always
  /// prints. A credit stays positive and takes "+" from `showPlus`. The
  /// magnitude comes from `amountMinor`, and the direction decides the sign,
  /// the same as `TransactionRow.amountText`.
  static func signedMinor(amountMinor: Int, direction: Direction) -> Int {
    direction == .credit ? abs(amountMinor) : -abs(amountMinor)
  }

  /// A-03 item 3: the spoken label carries the direction word, so the sign and
  /// the colour are never the only signal.
  static func accessibilityLabel(
    title: String,
    direction: Direction,
    amountMinor: Int,
    currencyCode: String,
    categoryName: String?
  ) -> String {
    let word = direction == .credit ? "credit" : "debit"
    let amount = NomiFormatters.amountString(minor: abs(amountMinor), currencyCode: currencyCode)
    return "\(title), \(word) \(amount), \(subtitle(categoryName: categoryName))"
  }
}

/// Card 7 (HM2, Main artboard): the five most recent transactions across all
/// accounts, newest first. Each 64 pt row opens the Detail sheet through
/// `onSelect`. The "Recent" header is drawn by `DashboardView`, so the card has
/// no title of its own.
public struct RecentTransactionsCard: View {
  public let transactions: [NomiCore.Transaction]
  public let badges: [UUID: CategoryBadge]
  public let onSelect: ((UUID) -> Void)?

  public init(transactions: [NomiCore.Transaction], badges: [UUID: CategoryBadge] = [:], onSelect: ((UUID) -> Void)? = nil) {
    self.transactions = transactions
    self.badges = badges
    self.onSelect = onSelect
  }

  private var recent: [NomiCore.Transaction] {
    RecentRows.mostRecent(transactions, limit: 5)
  }

  public var body: some View {
    if recent.isEmpty {
      Text("No transactions yet")
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget, alignment: .leading)
        .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    } else {
      VStack(spacing: 0) {
        ForEach(Array(recent.enumerated()), id: \.element.id) { index, transaction in
          row(for: transaction, showsDivider: index < recent.count - 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard(padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
  }

  /// A 64 pt row. The 1 pt divider is an overlay on the row's bottom edge, so
  /// the row stays 64 pt with or without it, as on the artboard.
  private func row(for transaction: NomiCore.Transaction, showsDivider: Bool) -> some View {
    let badge = transaction.categoryID.flatMap { badges[$0] }
    let categoryName = badge?.name
    let title = RecentRowText.title(
      merchantName: transaction.merchantName,
      descriptionText: transaction.descriptionText,
      categoryName: categoryName
    )
    let isCredit = transaction.direction == .credit
    return Button {
      onSelect?(transaction.id)
    } label: {
      HStack(alignment: .center, spacing: 12) {
        NomiCategoryBadge(
          symbolName: badge?.symbolName ?? "questionmark",
          paletteSlot: nil,
          size: 40,
          style: .neutral
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
            .lineLimit(1)
          Text(RecentRowText.subtitle(categoryName: categoryName))
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        DashboardAmountText(
          minor: RecentRowText.signedMinor(amountMinor: transaction.amountMinor, direction: transaction.direction),
          currencyCode: transaction.currencyCode,
          showPlus: isCredit,
          style: isCredit ? .amountStrong : .amount,
          colour: isCredit ? NomiColor.inkDeep : NomiColor.ink
        )
      }
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .overlay(alignment: .bottom) {
        if showsDivider {
          Rectangle()
            .fill(NomiColor.separator)
            .frame(height: 1)
        }
      }
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        RecentRowText.accessibilityLabel(
          title: title,
          direction: transaction.direction,
          amountMinor: transaction.amountMinor,
          currencyCode: transaction.currencyCode,
          categoryName: categoryName
        )
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview("Recent · default") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Recent · empty") {
  RecentTransactionsCard(transactions: [])
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Recent · accessibility 3") {
  RecentTransactionsCard(transactions: Array(PreviewData.transactions.prefix(5)))
    .padding()
    .background(NomiColor.ground)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}
