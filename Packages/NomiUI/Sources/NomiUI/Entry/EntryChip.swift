import SwiftUI

// clt-harness: include

/// The card surface the entry sheet's amount, type, chip and note rows share:
/// `card` fill, a 1 pt `separator` stroke and `NomiShadow.card`, at a radius the
/// caller passes (the Entry artboard uses 26 for the amount and type rows and 22
/// for chips and the note).
extension View {
  func entryCard(cornerRadius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return self
      .background {
        shape
          .fill(NomiColor.card)
          .shadow(
            color: NomiShadow.card.color,
            radius: NomiShadow.card.radius,
            x: NomiShadow.card.x,
            y: NomiShadow.card.y
          )
      }
      .overlay {
        shape.strokeBorder(NomiColor.separator, lineWidth: 1)
      }
  }
}

/// A prefilled, tappable chip on the entry sheet: Category, Account, Date, in
/// that order. Done-when the artboard matches: 44 pt high, radius 22, `card`
/// fill, `rowTitle` text, and the value alone (no field name) at normal sizes.
///
/// At `dynamicTypeSize >= .accessibility1` the same control draws as a
/// full-width row, 52 pt high, with the field name left, the value right and a
/// chevron, so a long value wraps instead of pushing the layout sideways. Either
/// way the button is labelled "<name>, <value>", since the name is not always
/// visible.
struct EntryChip: View {
  let name: String
  let value: String
  /// True for a placeholder value ("Unassigned", "Uncategorized"), drawn in
  /// `inkSecondary` so a chosen value reads as the stronger of the two.
  let isPlaceholder: Bool
  let leadingColor: Color?
  let action: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Button(action: action) {
      if dynamicTypeSize >= .accessibility1 {
        stackedLabel
      } else {
        inlineLabel
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(name), \(value)")
  }

  private var valueColor: Color {
    isPlaceholder ? NomiColor.inkSecondary : NomiColor.ink
  }

  private var inlineLabel: some View {
    HStack(spacing: NomiSpacing.xs) {
      if let leadingColor {
        Circle()
          .fill(leadingColor)
          .frame(width: 10, height: 10)
          .accessibilityHidden(true)
      }
      Text(value)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(valueColor)
        .fixedSize()
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(minHeight: NomiSpacing.minTarget)
    .entryCard(cornerRadius: 22)
    .contentShape(Capsule(style: .continuous))
  }

  private var stackedLabel: some View {
    HStack(spacing: NomiSpacing.xs) {
      Text(name)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
      Spacer(minLength: NomiSpacing.xs)
      if let leadingColor {
        Circle()
          .fill(leadingColor)
          .frame(width: 10, height: 10)
          .accessibilityHidden(true)
      }
      Text(value)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(valueColor)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
      Image(systemName: "chevron.right")
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    .entryCard(cornerRadius: 22)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

#Preview("Entry chips · default") {
  EntryChipFlowLayout(spacing: NomiSpacing.xs) {
    EntryChip(name: "Category", value: "Food & Dining", isPlaceholder: false, leadingColor: paletteSlot(0), action: {})
    EntryChip(name: "Account", value: "Unassigned", isPlaceholder: true, leadingColor: nil, action: {})
    EntryChip(name: "Date", value: "Today", isPlaceholder: false, leadingColor: nil, action: {})
  }
  .padding(NomiSpacing.screenGutter)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Entry chips · AX3") {
  VStack(spacing: NomiSpacing.xs) {
    EntryChip(name: "Category", value: "Food & Dining", isPlaceholder: false, leadingColor: paletteSlot(0), action: {})
    EntryChip(name: "Account", value: "Unassigned", isPlaceholder: true, leadingColor: nil, action: {})
    EntryChip(name: "Date", value: "Today", isPlaceholder: false, leadingColor: nil, action: {})
  }
  .padding(NomiSpacing.screenGutter)
  .frame(maxWidth: .infinity, alignment: .leading)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
