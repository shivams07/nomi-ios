import NomiCore
import SwiftUI

// clt-harness: include

/// The Expense / Income control, directly under the amount (Entry artboard): a
/// 52 pt card track with two 44 pt segments. The selected segment is `navy` with
/// `onPrimary` text; the other reads `inkDeep`. Defaults to `.debit`
/// (`EntryDefaults.direction`). It is an optional override, never a gate to Save.
struct DirectionToggle: View {
  @Binding var direction: Direction

  var body: some View {
    HStack(spacing: NomiSpacing.xxs) {
      segment(.debit, label: "Expense", systemImage: "arrow.down")
      segment(.credit, label: "Income", systemImage: "arrow.up")
    }
    .padding(NomiSpacing.xxs)
    .frame(maxWidth: .infinity, minHeight: 52)
    .entryCard(cornerRadius: 26)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Transaction type")
  }

  private func segment(_ value: Direction, label: String, systemImage: String) -> some View {
    let isSelected = direction == value
    return Button {
      direction = value
    } label: {
      HStack(spacing: NomiSpacing.xxs) {
        Image(systemName: systemImage)
          .imageScale(.medium)
        Text(label)
      }
      .font(.custom(isSelected ? NomiFont.interSemiBold : NomiFont.interMedium, size: 15, relativeTo: .body))
      .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.inkDeep)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
      .background {
        Capsule(style: .continuous)
          .fill(isSelected ? NomiColor.navy : Color.clear)
      }
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

#Preview("Direction toggle · expense selected") {
  DirectionToggle(direction: .constant(.debit))
    .padding(NomiSpacing.screenGutter)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Direction toggle · income selected") {
  DirectionToggle(direction: .constant(.credit))
    .padding(NomiSpacing.screenGutter)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}
