import SwiftUI

// clt-harness: include

#if canImport(UIKit)
import UIKit

/// The navigation-bar appearance for H0 screens (F3, I-4; SIMP §1).
///
/// The bar is opaque on `ground`. At the scroll edge it has no shadow. When
/// collapsed it draws a `separator` line. The large title is Inter SemiBold 34
/// with -0.4 tracking, in `ink`. The inline title is SemiBold 17. Bar button
/// items are Medium 17 in `navy`. The back button has no visible title, and
/// the tint is `navy`.
///
/// Call `configure()` once, after `NomiFont.registerIfNeeded()`. If the Inter
/// faces are not registered, the system font stands in.
public enum NomiNavigationAppearance {
  @MainActor
  public static func configure() {
    let ink = UIColor(NomiColor.ink)
    let navy = UIColor(NomiColor.navy)
    let ground = UIColor(NomiColor.ground)

    let standard = UINavigationBarAppearance()
    standard.configureWithOpaqueBackground()
    standard.backgroundColor = ground
    standard.shadowColor = UIColor(NomiColor.separator)

    let scrollEdge = UINavigationBarAppearance()
    scrollEdge.configureWithOpaqueBackground()
    scrollEdge.backgroundColor = ground
    scrollEdge.shadowColor = nil

    let buttonFont = font(named: NomiFont.interMedium, size: 17, weight: .medium)
    let buttonAttributes: [NSAttributedString.Key: Any] = [
      .font: buttonFont,
      .foregroundColor: navy,
    ]
    let backButtonAttributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: UIColor.clear,
    ]

    for appearance in [standard, scrollEdge] {
      appearance.largeTitleTextAttributes = [
        .font: font(named: NomiFont.interSemiBold, size: 34, weight: .semibold),
        .foregroundColor: ink,
        .kern: -0.4,
      ]
      appearance.titleTextAttributes = [
        .font: font(named: NomiFont.interSemiBold, size: 17, weight: .semibold),
        .foregroundColor: ink,
      ]
      appearance.buttonAppearance.normal.titleTextAttributes = buttonAttributes
      appearance.buttonAppearance.highlighted.titleTextAttributes = buttonAttributes
      appearance.buttonAppearance.disabled.titleTextAttributes = buttonAttributes
      appearance.backButtonAppearance.normal.titleTextAttributes = backButtonAttributes
      appearance.backButtonAppearance.highlighted.titleTextAttributes = backButtonAttributes
      appearance.backButtonAppearance.disabled.titleTextAttributes = backButtonAttributes
    }

    let proxy = UINavigationBar.appearance()
    proxy.standardAppearance = standard
    proxy.compactAppearance = standard
    proxy.scrollEdgeAppearance = scrollEdge
    proxy.compactScrollEdgeAppearance = scrollEdge
    proxy.tintColor = navy
  }

  /// The named Inter face, or the system font at `weight` when it is not registered.
  private static func font(named name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
    UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
  }
}
#else
/// No-op off UIKit platforms. The harness compiles this branch on macOS.
public enum NomiNavigationAppearance {
  @MainActor
  public static func configure() {}
}
#endif
