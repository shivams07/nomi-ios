import SwiftUI

// clt-harness: include

/// The two glass treatments (SIMP §1 rules 3 and 7; F3 of nomi-ios-build-plan,
/// I-4). `.tabBar` is the floating tab bar (F3a). `.heroControl` is dark glass on a
/// hero or the Backfill gradient.
public enum NomiGlassKind: Sendable {
  case tabBar
  case heroControl
}

/// The tab bar's own colours and shadow (F3a, I-16). They have no `NomiHex` name:
/// the `+` gradient and the selected highlight belong to the bar, so they sit here
/// with the glass that draws them.
public enum NomiGlass {
  /// The `+` circle's gradient, top to bottom.
  public static let addTop = Color(hex: 0x52764C)
  public static let addBottom = Color(hex: 0x33503A)
  /// The selected circle's inner top highlight: white at 28%, 1 pt.
  public static let selectedHighlight = Color(hex: NomiHex.white, opacity: 0.28)

  /// The tab bar's shadow, under every treatment (plan, "the only shadow is under the tab bar").
  static let tabBarShadow = NomiShadow(
    color: Color(hex: NomiHex.navyDeep, opacity: 0.20),
    radius: 17,
    x: 0,
    y: 14
  )

  /// The blurred fallback for iOS 17 to 25: a white wash from `fallbackTop` to
  /// `fallbackBottom`, a `fallbackStroke` border and a `fallbackHighlight` top line.
  fileprivate static let fallbackTop = Color(hex: NomiHex.white, opacity: 0.50)
  fileprivate static let fallbackBottom = Color(hex: NomiHex.white, opacity: 0.22)
  fileprivate static let fallbackStroke = Color(hex: NomiHex.white, opacity: 0.75)
  fileprivate static let fallbackHighlight = Color(hex: NomiHex.white, opacity: 0.95)
}

public extension View {
  /// Draws `kind` glass behind the view, clipped to `shape`.
  ///
  /// With Reduce Transparency on, the material is dropped for a solid fill:
  /// `card` for the tab bar, `heroGlassSolid` for a hero control.
  func nomiGlass<S: InsettableShape>(_ kind: NomiGlassKind, in shape: S) -> some View {
    modifier(NomiGlassModifier(kind: kind, shape: shape))
  }
}

private struct NomiGlassModifier<S: InsettableShape>: ViewModifier {
  let kind: NomiGlassKind
  let shape: S

  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    content.background {
      switch kind {
      case .tabBar:
        tabBarGlass
      case .heroControl:
        heroGlass
      }
    }
  }

  /// The floating tab bar's glass (F3a). With Reduce Transparency, a solid `card` fill
  /// and a 1 pt separator stroke. Otherwise iOS 26 draws the system Liquid Glass, and
  /// iOS 17 to 25 draw the blurred translucent fallback. Every treatment keeps the
  /// tab-bar shadow.
  private var tabBarGlass: some View {
    ZStack {
      if reduceTransparency {
        shape.fill(NomiColor.card)
        shape.strokeBorder(NomiColor.separator, lineWidth: 1)
      } else {
        tabBarMaterial
      }
    }
    .shadow(
      color: NomiGlass.tabBarShadow.color,
      radius: NomiGlass.tabBarShadow.radius,
      x: NomiGlass.tabBarShadow.x,
      y: NomiGlass.tabBarShadow.y
    )
  }

  /// `glassEffect` is iOS 26 API. CI's Xcode 16.2 has no such symbol, so the code that
  /// names it sits behind the compiler check, and that build takes the fallback.
  @ViewBuilder
  private var tabBarMaterial: some View {
    #if compiler(>=6.2)
      if #available(iOS 26, macOS 26, *) {
        Color.clear.glassEffect(.regular, in: shape)
      } else {
        tabBarFallback
      }
    #else
      tabBarFallback
    #endif
  }

  /// `.ultraThinMaterial`, a white wash from top to bottom, a 1 pt stroke and a 1.5 pt
  /// highlight along the top edge.
  private var tabBarFallback: some View {
    ZStack {
      shape.fill(.ultraThinMaterial)
      shape.fill(
        LinearGradient(
          colors: [NomiGlass.fallbackTop, NomiGlass.fallbackBottom],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      shape.strokeBorder(NomiGlass.fallbackStroke, lineWidth: 1)
      VStack(spacing: 0) {
        Rectangle()
          .fill(NomiGlass.fallbackHighlight)
          .frame(height: 1.5)
        Spacer(minLength: 0)
      }
      .clipShape(shape)
    }
  }

  /// `heroGlassFill` (`heroGlassTint` at 52%) alone, a 1 pt `heroGlassBorder`
  /// stroke and a 1 pt `heroGlassHighlight` line along the top edge. No
  /// material: the light `.ultraThinMaterial` washed the navy to grey (D3).
  private var heroGlass: some View {
    ZStack {
      if reduceTransparency {
        shape.fill(NomiColor.heroGlassSolid)
      } else {
        shape.fill(NomiColor.heroGlassFill)
      }
      shape.strokeBorder(NomiColor.heroGlassBorder, lineWidth: 1)
      VStack(spacing: 0) {
        Rectangle()
          .fill(NomiColor.heroGlassHighlight)
          .frame(height: 1)
        Spacer(minLength: 0)
      }
      .clipShape(shape)
    }
  }
}

#Preview("Tab glass and hero glass · default") {
  ZStack {
    NomiColor.ground.ignoresSafeArea()
    VStack(spacing: 24) {
      Text("Tab bar glass")
        .frame(width: NomiTabBarMetrics.barWidth, height: NomiTabBarMetrics.barHeight)
        .nomiGlass(.tabBar, in: Capsule())
      Text("Hero glass")
        .foregroundStyle(NomiColor.heroText)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(NomiHeroGradient.gradient(height: 200, safeTop: 54))
        .nomiGlass(.heroControl, in: Capsule())
    }
    .padding(20)
  }
  .preferredColorScheme(.light)
}

#Preview("Tab glass and hero glass · AX3") {
  ZStack {
    NomiColor.ground.ignoresSafeArea()
    VStack(spacing: 24) {
      Text("Tab bar glass")
        .frame(width: NomiTabBarMetrics.barWidth, height: NomiTabBarMetrics.barHeight)
        .nomiGlass(.tabBar, in: Capsule())
      Text("Hero glass")
        .foregroundStyle(NomiColor.heroText)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(NomiHeroGradient.gradient(height: 200, safeTop: 54))
        .nomiGlass(.heroControl, in: Capsule())
    }
    .padding(20)
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
