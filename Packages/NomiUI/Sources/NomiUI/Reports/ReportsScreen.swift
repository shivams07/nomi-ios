import Foundation
import NomiCore
import SwiftUI

/// The Reports/Insights page (U13, v5 new) — the largest of the four new
/// screens. Calendar-month vs financial-year toggle drives every figure via
/// `ReportsViewModel`; income-vs-expense trend; category breakdown; CSV
/// export via `ShareLink`.
///
/// Archived accounts are never excluded here (unlike the dashboard's accounts
/// card) — `insightsStore.insights(for:)`/`.transactions(in:)` don't filter
/// by account at all, so this AC ("archiving must not change a number on
/// Reports") holds by construction: this screen simply never calls
/// `accountSummaries(includeArchived:)`.
public struct ReportsScreen: View {
  public let insightsStore: InsightsStore

  @State private var basis: PeriodBasis
  @State private var anchor: Date
  @State private var exportURL: URL?
  @State private var exportError = false

  public init(insightsStore: InsightsStore, initialBasis: PeriodBasis = .calendarMonth, initialAnchor: Date = Date()) {
    self.insightsStore = insightsStore
    _basis = State(initialValue: initialBasis)
    _anchor = State(initialValue: initialAnchor)
  }

  private var period: InsightPeriod {
    ReportsPeriod.period(basis: basis, anchor: anchor)
  }

  private var viewModel: ReportsViewModel? {
    guard let insights = try? insightsStore.insights(for: period) else { return nil }
    let trend = (try? insightsStore.trend(months: ReportsPeriod.trendMonths(for: basis))) ?? []
    return ReportsViewModelBuilder.make(period: period, insights: insights, trend: trend)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardToCard) {
        periodSelector
        if let viewModel {
          summarySection(viewModel)
          ReportsTrendCard(trend: viewModel.trend)
          ReportsCategoryBreakdownCard(slices: viewModel.categories)
          exportButton
        } else {
          Text("No data for this period")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Reports")
    .alert("Could not export CSV", isPresented: $exportError) {
      Button("OK", role: .cancel) {}
    }
  }

  private var periodSelector: some View {
    HStack(spacing: NomiSpacing.sm) {
      Button {
        anchor = ReportsPeriod.shiftedAnchor(anchor, basis: basis, by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .foregroundStyle(NomiColor.textSecondary)
      }
      Text(ReportsPeriod.label(for: period))
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        anchor = ReportsPeriod.shiftedAnchor(anchor, basis: basis, by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.textSecondary)
      }
      NomiSegmentedPill(basis: $basis)
    }
  }

  private func summarySection(_ viewModel: ReportsViewModel) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack {
        summaryFigure(label: "Received", amountMinor: viewModel.creditMinor, delta: viewModel.creditDelta)
        Spacer(minLength: NomiSpacing.sm)
        summaryFigure(label: "Spent", amountMinor: viewModel.debitMinor, delta: viewModel.debitDelta)
      }
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRaised)
    .nomiCornerRadius(NomiRadius.card)
  }

  private func summaryFigure(label: String, amountMinor: Int, delta: ReportsDelta.Result?) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(label)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      Text(NomiFormatters.amountString(minor: amountMinor))
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 20))
        .foregroundStyle(NomiColor.textPrimary)
      if let delta {
        Text("\(delta.isIncrease ? "▲" : "▼") \(ReportsDelta.percentText(delta.percent)) vs last period")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      } else {
        Text("No prior period to compare")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  @ViewBuilder
  private var exportButton: some View {
    if let exportURL {
      ShareLink(item: exportURL) {
        Label("Export CSV", systemImage: "square.and.arrow.up")
      }
    } else {
      Button {
        performExport()
      } label: {
        Label("Export CSV", systemImage: "square.and.arrow.up")
      }
    }
  }

  private func performExport() {
    guard let transactions = try? insightsStore.transactions(in: period) else {
      exportError = true
      return
    }
    guard let url = try? ReportsCSVExport.write(transactions) else {
      exportError = true
      return
    }
    exportURL = url
  }
}

private let previewAnchor = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 15))!

#Preview("Reports — calendar month, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Reports — financial year, same underlying data, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .financialYear,
      initialAnchor: previewAnchor
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Reports — 3 months of data, 3 trend bars, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 3, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Reports — zero data, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 0, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Reports — accessibility 3, dark") {
  NavigationStack {
    ReportsScreen(
      insightsStore: ReportsPreviewSupport.makeInsightsStore(monthCount: 12, anchor: previewAnchor),
      initialBasis: .calendarMonth,
      initialAnchor: previewAnchor
    )
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
