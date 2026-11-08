import SwiftUI

/// The app's root chrome: the flat ground (`#F3F6FB`) that every screen sits on. The tab bar is `NomiTabBar` (F3), placed by `RootView`
/// over this shell; this view draws no bar of its own.
public struct NomiTabShell<Content: View>: View {
  public let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    ZStack {
      NomiColor.ground.ignoresSafeArea()
      content
    }
    .background(NomiColor.ground)
  }
}

#Preview("Tab shell — card stack on the ground") {
  NomiTabShell {
    ScrollView {
      VStack(spacing: NomiSpacing.sm) {
        ForEach(0..<8) { index in
          RoundedRectangle(cornerRadius: NomiRadius.card, style: .continuous)
            .fill(NomiColor.card)
            .frame(height: 64)
            .overlay(Text("Card \(index)").foregroundStyle(NomiColor.textPrimary))
        }
      }
      .padding(NomiSpacing.screenGutter)
    }
  }
  .preferredColorScheme(.light)
}
