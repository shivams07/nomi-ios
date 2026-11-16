import Foundation
import NomiCore
import SwiftUI

/// "Top merchants" on Insights (S6): the four largest for the period, each with
/// an initials tile, its payment count and the whole-rupee total. Replaces the
/// Dashboard's `TopMerchantsCard` on this screen.
struct ReportsMerchantsCard: View {
  let merchants: [MerchantTotal]

  /// The rows shown.
  static let rowLimit = 4

  init(merchants: [MerchantTotal]) {
    self.merchants = merchants
  }

  /// "1 payment", "6 payments". The count is `MerchantTotal.count`, the rows
  /// folded into the total.
  static func paymentsLine(count: Int) -> String {
    String(localized: "\(count) payments", bundle: .module)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("Top merchants", bundle: .module)
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .padding(.bottom, NomiSpacing.xxs)
      if merchants.isEmpty {
        Text("No merchants this period", bundle: .module)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      } else {
        ForEach(merchants.prefix(Self.rowLimit)) { merchant in
          row(merchant)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  private func row(_ merchant: MerchantTotal) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Text(verbatim: TransactionRow.initials(for: merchant.label))
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.navy)
        .frame(width: 36, height: 36)
        .background(Circle().fill(NomiColor.iconTile))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: merchant.label)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        Text(verbatim: Self.paymentsLine(count: merchant.count))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(verbatim: ReportsRupees.whole(minor: merchant.totalMinor))
        .nomiTextStyle(.amount)
        .foregroundStyle(NomiColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(minHeight: NomiSpacing.rowMinHeight)
    .accessibilityElement(children: .combine)
  }
}
