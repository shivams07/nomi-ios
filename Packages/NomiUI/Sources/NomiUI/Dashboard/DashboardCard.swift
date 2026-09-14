import SwiftUI

/// The one card shell every dashboard module uses. Per the U9 done-when: no
/// border, no shadow — depth comes from the fill step alone, not from
/// `nomiShadow()` or a hairline stroke. Fill is `NomiColor.surfaceRaised`,
/// `#1C2130` since v5's `nomi-ui-refresh` (the U9 done-when named `#212121`,
/// which M1 superseded).
struct DashboardCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(NomiSpacing.cardPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(NomiColor.surfaceRaised)
      .nomiCornerRadius(NomiRadius.card)
  }
}
