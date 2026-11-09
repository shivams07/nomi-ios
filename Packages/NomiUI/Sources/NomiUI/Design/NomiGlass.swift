import SwiftUI

// clt-harness: include

/// The two glass treatments (SIMP §1 rules 3 and 7; F3 of nomi-ios-build-plan,
/// I-4). `.tabBar` is the floating tab bar. `.heroControl` is dark glass on a
/// hero or the Backfill gradient.
public enum NomiGlassKind: Sendable {
  case tabBar
  case heroControl
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

  /// `.ultraThinMaterial`, a 135° wash from `tabGlassTop` to `tabGlassBottom`,
  /// a 1 pt `tabGlassBorder` stroke and the tab-bar shadow.
  private var tabBarGlass: some View {
    ZStack {
      if reduceTransparency {
        shape.fill(NomiColor.card)
      } else {
        shape.fill(.ultraThinMaterial)
        shape.fill(
          LinearGradient(
            colors: [NomiColor.tabGlassTop, NomiColor.tabGlassBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
      shape.strokeBorder(NomiColor.tabGlassBorder, lineWidth: 1)
    }
    .shadow(
      color: NomiShadow.tabBar.color,
      radius: NomiShadow.tabBar.radius,
      x: NomiShadow.tabBar.x,
      y: NomiShadow.tabBar.y
    )
  }

  /// `heroGlassFill` (navyDeep at 30%) alone, a 1 pt `heroGlassBorder` stroke
  /// and a 1 pt `heroGlassHighlight` line along the top edge. No material: the
  /// light `.ultraThinMaterial` washed the navy to grey (D3, fidelity sweep).
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
        .padding(.horizontal, 24)
        .frame(height: 64)
        .nomiGlass(.tabBar, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
        .padding(.horizontal, 24)
        .frame(height: 64)
        .nomiGlass(.tabBar, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
