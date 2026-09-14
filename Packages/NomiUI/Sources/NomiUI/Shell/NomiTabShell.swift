import SwiftUI

/// The app's root chrome. Content sits directly on the navy-black canvas
/// behind a floating glass tab bar. v5 (`nomi-ui-refresh`) removes the two
/// glow-orb circles that used to render once behind the tab content.
/// `NomiGlow` itself stays, its one remaining consumer is the tab-bar `+`
/// (wired in `ui-root-wiring`, not here).
public struct NomiTabShell<Content: View>: View {
  public let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    ZStack {
      NomiColor.surfaceCanvas.ignoresSafeArea()
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

#Preview("Tab shell — card stack on the v5 navy-black ground") {
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
