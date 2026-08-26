import SwiftUI

/// The app's root chrome. Renders the glow-orb atmosphere ONCE behind the tab
/// content — never per card, never per row — and a floating glass tab bar.
public struct NomiTabShell<Content: View>: View {
  public let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    ZStack {
      NomiColor.surfaceCanvas.ignoresSafeArea()
      NomiGlowOrbs()
      content
    }
    .background(NomiColor.surfaceCanvas)
  }
}

/// The floating glass tab bar chrome — radius 24, blur 12, the system's
/// declared shadow.
public struct NomiFloatingTabBarBackground: View {
  public init() {}

  public var body: some View {
    RoundedRectangle(cornerRadius: NomiRadius.bar, style: .continuous)
      .fill(NomiColor.floatingGlassFill)
      .overlay(
        RoundedRectangle(cornerRadius: NomiRadius.bar, style: .continuous)
          .stroke(NomiColor.floatingGlassHairline, lineWidth: 1)
      )
      .nomiShadow()
  }
}

#Preview("Tab shell — glow orbs once behind content") {
  NomiTabShell {
    ScrollView {
      VStack(spacing: NomiSpacing.sm) {
        ForEach(0..<8) { index in
          RoundedRectangle(cornerRadius: NomiRadius.card, style: .continuous)
            .fill(NomiColor.surfaceRaised)
            .frame(height: 64)
            .overlay(Text("Card \(index)").foregroundStyle(NomiColor.textPrimary))
        }
      }
      .padding(NomiSpacing.screenGutter)
    }
  }
  .preferredColorScheme(.dark)
}
