import SwiftUI

/// The one card shell the Home modules and the Budgets cards draw with. It is
/// F3's `nomiCard` with the Home 16 pt inset: card fill, 24 pt continuous
/// corners, a 1 pt separator and the card shadow. The init is unchanged.
struct DashboardCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }
}

/// A signed amount drawn in a colour the caller chooses. `NomiAmountText` draws
/// its primary in `ink` and has no colour parameter, so the rows that need
/// DEC-03's credit colour, and the over-budget figure that needs `error`, draw
/// through this view. Sign and decimal split come from `NomiAmountFormat`, so
/// the typesetting matches every other amount, and the decimals are dimmed the
/// same way (`decimalOpacityGround`).
struct DashboardAmountText: View {
  let minor: Int
  var currencyCode: String = "INR"
  var showPlus: Bool = false
  let style: NomiTextStyle
  let colour: Color

  var body: some View {
    let parts = NomiAmountFormat.parts(minor: minor, currencyCode: currencyCode, showPlus: showPlus)
    (Text(parts.sign + parts.integer)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(colour)
      + Text(parts.decimals)
      .font(style.font)
      .tracking(style.tracking)
      .foregroundStyle(colour.opacity(NomiColor.decimalOpacityGround)))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  }
}

#Preview("Dashboard card · default") {
  DashboardCard {
    Text("Card content")
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.ink)
  }
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}
