import NomiCore
import SwiftUI

/// Card 4: the top-5 merchant rollup. Distinct from `RecentTransactionsCard`
/// — this is a rollup by merchant total, not a list of individual rows.
/// `MerchantTotal.label` is already `merchantName ?? descriptionText` (§2.4),
/// resolved once in `InsightsStore`, so this view never re-derives it.
public struct TopMerchantsCard: View {
  public let merchants: [MerchantTotal]

  public init(merchants: [MerchantTotal]) {
    self.merchants = merchants
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Top merchants")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if merchants.isEmpty {
          Text("No merchant spend yet")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          VStack(spacing: NomiSpacing.xs) {
            ForEach(Array(merchants.enumerated()), id: \.element.id) { index, merchant in
              HStack(spacing: NomiSpacing.xs) {
                Text("\(index + 1)")
                  .nomiTextStyle(.caption)
                  .foregroundStyle(NomiColor.textQuaternary)
                  .frame(width: 16, alignment: .leading)
                Text(merchant.label)
                  .nomiTextStyle(.body)
                  .foregroundStyle(NomiColor.textPrimary)
                  .lineLimit(1)
                Spacer(minLength: NomiSpacing.xs)
                Text(NomiFormatters.amountString(minor: merchant.totalMinor))
                  .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
                  .foregroundStyle(NomiColor.textSecondary)
              }
            }
          }
        }
      }
    }
  }
}

#Preview("Top merchants — default, dark") {
  TopMerchantsCard(merchants: [
    MerchantTotal(id: "SWIGGY", label: "SWIGGY", totalMinor: 4500_00),
    MerchantTotal(id: "AMAZON", label: "AMAZON", totalMinor: 3200_00),
    MerchantTotal(id: "UBER", label: "UBER", totalMinor: 2100_00),
    MerchantTotal(id: "ZOMATO", label: "ZOMATO", totalMinor: 1800_00),
    MerchantTotal(id: "FLIPKART", label: "FLIPKART", totalMinor: 1200_00),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Top merchants — empty, dark") {
  TopMerchantsCard(merchants: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Top merchants — accessibility 3, dark") {
  TopMerchantsCard(merchants: [
    MerchantTotal(id: "SWIGGY", label: "SWIGGY", totalMinor: 4500_00),
    MerchantTotal(id: "AMAZON", label: "AMAZON", totalMinor: 3200_00),
    MerchantTotal(id: "UBER", label: "UBER", totalMinor: 2100_00),
    MerchantTotal(id: "ZOMATO", label: "ZOMATO", totalMinor: 1800_00),
    MerchantTotal(id: "FLIPKART", label: "FLIPKART", totalMinor: 1200_00),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
