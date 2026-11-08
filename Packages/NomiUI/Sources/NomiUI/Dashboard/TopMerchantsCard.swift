import Foundation
import NomiCore
import SwiftUI

// clt-harness: include

/// "Top merchants" on Insights: the top merchants by total, with an initials
/// tile per row. Totals only, no order counts and no rank. `MerchantTotal.label`
/// is already `merchantName ?? descriptionText` (§2.4), resolved once in
/// `InsightsStore`, so this view never re-derives it. It moved here from Home
/// (SIMP §1); the initializer is unchanged so Home compiles until HM1 removes it.
public struct TopMerchantsCard: View {
  public let merchants: [MerchantTotal]

  public init(merchants: [MerchantTotal]) {
    self.merchants = merchants
  }

  /// Two letters for the row's initials tile, from the merchant label.
  static func initials(for label: String) -> String {
    String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("Top merchants")
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
      if merchants.isEmpty {
        Text("No merchant spend yet")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      } else {
        VStack(spacing: 0) {
          ForEach(merchants) { merchant in
            HStack(spacing: NomiSpacing.cardGap) {
              Text(Self.initials(for: merchant.label))
                .nomiTextStyle(.micro)
                .foregroundStyle(NomiColor.iconGlyph)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NomiColor.iconTile))
                .accessibilityHidden(true)
              Text(merchant.label)
                .nomiTextStyle(.rowTitle)
                .foregroundStyle(NomiColor.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
              NomiAmountText(minor: merchant.totalMinor, style: .amount)
            }
            .frame(minHeight: NomiSpacing.minTarget)
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 134, alignment: .topLeading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }
}

#Preview("Top merchants · default") {
  TopMerchantsCard(merchants: [
    MerchantTotal(id: "SWIGGY", label: "Swiggy", totalMinor: 5420_00),
    MerchantTotal(id: "AMAZON", label: "Amazon", totalMinor: 4180_50),
    MerchantTotal(id: "UBER", label: "Uber", totalMinor: 2100_00),
  ])
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Top merchants · empty") {
  TopMerchantsCard(merchants: [])
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Top merchants · AX3") {
  TopMerchantsCard(merchants: [
    MerchantTotal(id: "SWIGGY", label: "Swiggy", totalMinor: 5420_00),
    MerchantTotal(id: "AMAZON", label: "Amazon", totalMinor: 4180_50),
  ])
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
