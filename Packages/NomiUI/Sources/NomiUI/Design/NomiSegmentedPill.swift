import NomiCore
import SwiftUI

/// FY / calendar-month toggle. U13 owns the Reports screen but U9 may later
/// show this same control on the dashboard, so it lives here rather than
/// being rebuilt per-screen.
public struct NomiSegmentedPill: View {
  @Binding public var basis: PeriodBasis

  public init(basis: Binding<PeriodBasis>) {
    self._basis = basis
  }

  public var body: some View {
    HStack(spacing: 0) {
      segment(.calendarMonth, label: "Calendar")
      segment(.financialYear, label: "FY")
    }
    .padding(NomiSpacing.xxs / 2)
    .background(NomiColor.surface)
    .clipShape(Capsule(style: .continuous))
  }

  private func segment(_ value: PeriodBasis, label: String) -> some View {
    let isSelected = basis == value
    return Text(label)
      .nomiTextStyle(.caption)
      .foregroundStyle(isSelected ? NomiColor.textPrimary : NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xxs)
      .background(isSelected ? NomiColor.accent : Color.clear)
      .clipShape(Capsule(style: .continuous))
      .onTapGesture { basis = value }
  }
}
