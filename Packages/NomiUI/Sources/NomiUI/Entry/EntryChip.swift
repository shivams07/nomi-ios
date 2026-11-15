import SwiftUI

// clt-harness: include

/// The card surface the entry sheet's amount, payee and detail rows share: `card`
/// fill, a 1 pt `separator` stroke and `NomiShadow.card`, at a radius the caller
/// passes (the Add artboard uses 28 for the detail card, 22 for the payee field).
///
/// S5 removed the old Category, Account and Date chip control. The category
/// suggestions are NomiChip, and the detail rows are card rows in EntryView.
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
