import SwiftUI

/// The one card shell every dashboard module uses. Per the U9 done-when: fill
/// `#212121` (`NomiColor.surfaceRaised`), no border, no shadow — depth comes
/// from the fill step alone, not from `nomiShadow()` or a hairline stroke.
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
