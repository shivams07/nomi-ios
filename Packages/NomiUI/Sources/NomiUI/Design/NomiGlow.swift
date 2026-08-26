import SwiftUI

/// Places a `RadialGradient` ellipse behind the modified element, accent hue,
/// low alpha, roughly 1.6x the element's bounds. Deliberately not a
/// `.shadow(color:radius:)` (the floating-glass shadow is the system's only
/// shadow) and not a live `.blur()` (forces offscreen rendering every frame;
/// this rasterises once and costs a fill instead).
///
/// May only be applied to elements that do not scroll — the tab-bar `+`, a
/// bottom-anchored primary button, the dashboard hero card. **Never a ledger
/// row.** That is a hard rule, not a preference.
public struct NomiGlow: ViewModifier {
  public let scale: CGFloat

  public init(scale: CGFloat = 1.6) {
    self.scale = scale
  }

  public func body(content: Content) -> some View {
    content.background(
      GeometryReader { proxy in
        let width = proxy.size.width * scale
        let height = proxy.size.height * scale
        RadialGradient(
          colors: [NomiColor.accent.opacity(0.22), NomiColor.accent.opacity(0)],
          center: .center,
          startRadius: 0,
          endRadius: max(width, height) / 2
        )
        .frame(width: width, height: height)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      }
    )
  }
}

public extension View {
  /// Do not apply inside a scrolling container, and never to a ledger row.
  func nomiGlow(scale: CGFloat = 1.6) -> some View {
    modifier(NomiGlow(scale: scale))
  }
}

/// The signature atmosphere: two 240px `#0162FE` circles at 14%, blurred 46px,
/// anchored partly off-canvas. Rendered ONCE behind the tab content — never
/// per card, never per row, so a scrolling list never pays for the blur.
public struct NomiGlowOrbs: View {
  public init() {}

  public var body: some View {
    GeometryReader { proxy in
      ZStack {
        Circle()
          .fill(Color(hex: 0x0162FE).opacity(0.14))
          .frame(width: 240, height: 240)
          .blur(radius: 46)
          .position(x: -40, y: proxy.size.height * 0.15)
        Circle()
          .fill(Color(hex: 0x0162FE).opacity(0.14))
          .frame(width: 240, height: 240)
          .blur(radius: 46)
          .position(x: proxy.size.width + 40, y: proxy.size.height * 0.75)
      }
    }
    .allowsHitTesting(false)
  }
}
