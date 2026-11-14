import SwiftUI

// clt-harness: include

public extension View {
  /// Puts the view on a card: `card` fill, 24 pt continuous corners, a 1 pt
  /// `separator` stroke and `NomiShadow.card`. The shadow is drawn on the card
  /// background, so content is not shadowed.
  func nomiCard(padding: EdgeInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)) -> some View {
    let shape = RoundedRectangle(cornerRadius: NomiRadius.card, style: NomiRadius.cardSheetStyle)
    return self
      .padding(padding)
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

#Preview("Card · default") {
  VStack(alignment: .leading, spacing: 4) {
    Text("HDFC Savings")
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.ink)
    Text("HDFC ••4471 · 42 transactions")
      .nomiTextStyle(.footnote)
      .foregroundStyle(NomiColor.inkSecondary)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
  .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Card · AX3") {
  VStack(alignment: .leading, spacing: 4) {
    Text("HDFC Savings")
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.ink)
    Text("HDFC ••4471 · 42 transactions")
      .nomiTextStyle(.footnote)
      .foregroundStyle(NomiColor.inkSecondary)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
  .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
