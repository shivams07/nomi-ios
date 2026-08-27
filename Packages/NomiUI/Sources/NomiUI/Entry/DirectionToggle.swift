import NomiCore
import SwiftUI

/// The debit/credit segmented control on the entry sheet. v4 amendment: gains
/// a per-segment icon. Defaults to `.debit` (`EntryDefaults.direction`) and is
/// never required to reach Save — it sits in the entry sheet as an optional
/// override, not a gate, per the done-when ("no ... segmented control ...
/// sits in that path").
struct DirectionToggle: View {
  @Binding var direction: Direction

  var body: some View {
    HStack(spacing: 0) {
      segment(.debit, label: "Expense", systemImage: "arrow.down")
      segment(.credit, label: "Income", systemImage: "arrow.up")
    }
    .padding(NomiSpacing.xxs / 2)
    .background(NomiColor.surface)
    .clipShape(Capsule(style: .continuous))
  }

  private func segment(_ value: Direction, label: String, systemImage: String) -> some View {
    let isSelected = direction == value
    return Button {
      direction = value
    } label: {
      HStack(spacing: NomiSpacing.xxs) {
        Image(systemName: systemImage)
        Text(label)
      }
      .nomiTextStyle(.caption)
      .foregroundStyle(isSelected ? NomiColor.textPrimary : NomiColor.textTertiary)
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xxs)
      .frame(maxWidth: .infinity)
      .background(isSelected ? NomiColor.accent : Color.clear)
      .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

#Preview("Direction toggle — expense selected, dark") {
  DirectionToggle(direction: .constant(.debit))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Direction toggle — income selected, dark") {
  DirectionToggle(direction: .constant(.credit))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}
