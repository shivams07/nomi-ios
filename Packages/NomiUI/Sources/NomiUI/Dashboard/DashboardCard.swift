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
