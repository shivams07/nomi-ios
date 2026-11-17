import Foundation
import NomiCore
import SwiftUI

/// "By category" on Insights (S6): a 14 pt stacked bar with 2 pt gaps, then one
/// row per `ReportsCategoryFold.Row`. A category row drills into Activity for
/// that category. The Uncategorised row drills into Activity's uncategorised
/// list, and its "Fix <n>" tag opens the Review queue. The folded row has no
/// drill-down: it is a group, not one category.
struct ReportsCategoryBreakdownCard: View {
  let breakdown: ReportsCategoryFold.Breakdown
  let uncategorizedCount: Int

  @Environment(\.nomiShowLedger) private var showLedger
  @Environment(\.nomiOpenReview) private var openReview

  init(breakdown: ReportsCategoryFold.Breakdown, uncategorizedCount: Int) {
    self.breakdown = breakdown
    self.uncategorizedCount = uncategorizedCount
  }

  var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
        Text("By category", bundle: .module)
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xs)
        Text("Tap to see transactions", bundle: .module)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      if breakdown.rows.isEmpty {
        Text("No categorised spend this period", bundle: .module)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      } else {
        stackedBar
        VStack(spacing: 0) {
          ForEach(breakdown.rows) { row in
            rowView(row)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  private var stackedBar: some View {
    GeometryReader { proxy in
      let gaps = CGFloat(max(0, breakdown.rows.count - 1)) * 2
      let usable = max(0, proxy.size.width - gaps)
      HStack(spacing: 2) {
        ForEach(breakdown.rows) { row in
          Rectangle()
            .fill(ReportsCategoryFold.colour(for: row.kind))
            .frame(width: usable * CGFloat(row.share))
        }
      }
    }
    .frame(height: 14)
    .clipShape(Capsule())
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func rowView(_ row: ReportsCategoryFold.Row) -> some View {
    switch row.kind {
    case .category:
      Button {
        showLedger?(.category(row.id))
      } label: {
        HStack(spacing: NomiSpacing.xs) {
          nameLine(row)
          Text(verbatim: "\(ReportsCategoryFold.percent(row.share))%")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
          amountText(row)
        }
        .frame(minHeight: NomiSpacing.rowMinHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    case .uncategorised:
      HStack(spacing: NomiSpacing.xs) {
        Button {
          showLedger?(.uncategorized)
        } label: {
          nameLine(row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Button {
          openReview?()
        } label: {
          NomiTag(String(localized: "Fix \(uncategorizedCount)", bundle: .module), tone: .warning)
        }
        .buttonStyle(.plain)
        Button {
          showLedger?(.uncategorized)
        } label: {
          amountText(row)
        }
        .buttonStyle(.plain)
      }
      .frame(minHeight: NomiSpacing.rowMinHeight)
    case .folded:
      HStack(spacing: NomiSpacing.xs) {
        nameLine(row)
        Text(verbatim: "\(ReportsCategoryFold.percent(row.share))%")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
        amountText(row)
      }
      .frame(minHeight: NomiSpacing.rowMinHeight)
    }
  }

  /// The row's dot and name. The name is the category's own, or the localised
  /// label for the uncategorised and folded rows.
  private func nameLine(_ row: ReportsCategoryFold.Row) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Circle()
        .fill(ReportsCategoryFold.colour(for: row.kind))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
      nameText(row)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func nameText(_ row: ReportsCategoryFold.Row) -> some View {
    switch row.kind {
    case .category:
      Text(verbatim: row.categoryName)
    case .uncategorised:
      Text("Uncategorised", bundle: .module)
    case .folded(let count):
      Text("\(count) more categories", bundle: .module)
    }
  }

  private func amountText(_ row: ReportsCategoryFold.Row) -> some View {
    Text(verbatim: ReportsRupees.whole(minor: row.totalMinor))
      .nomiTextStyle(.amount)
      .foregroundStyle(NomiColor.ink)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .frame(minWidth: 88, alignment: .trailing)
  }
}
