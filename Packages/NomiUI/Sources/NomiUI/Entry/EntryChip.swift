import SwiftUI

/// A prefilled, tappable pill for the entry sheet's date and category fields.
/// v4 amendment: chips gain a leading hue glyph — the category chip passes its
/// `paletteSlot` colour as `leadingColor`; the date chip passes `nil` since a
/// date has no hue.
struct EntryChip: View {
  let label: String
  let leadingColor: Color?
  let leadingSymbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xxs) {
        if let leadingColor {
          Circle()
            .fill(leadingColor)
            .frame(width: 8, height: 8)
        }
        Image(systemName: leadingSymbol)
          .font(.system(size: 12))
          .foregroundStyle(NomiColor.textSecondary)
        Text(label)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xs)
      .background(NomiColor.surface)
      .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

#Preview("Entry chips — date and category, dark") {
  HStack(spacing: NomiSpacing.xs) {
    EntryChip(label: "27 Aug 2026", leadingColor: nil, leadingSymbol: "calendar", action: {})
    EntryChip(label: "Food & Dining", leadingColor: paletteSlot(0), leadingSymbol: "fork.knife", action: {})
  }
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}
