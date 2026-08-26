import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias NomiPlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias NomiPlatformFont = NSFont
#endif

/// Montserrat is Nomi's primary face (Estate-Ease's Tailwind `sans` default,
/// same geometric-sans genre as Gilroy, OFL-licensed so embedding is
/// unambiguous). Inter is the secondary face for captions and small text.
/// Font files ship in `Resources/Fonts/**`; `App/Info.plist` declares
/// `UIAppFonts` with these exact filenames (U0, frozen) — this type must not
/// invent a different filename.
///
/// This file targets iOS at runtime but also compiles under plain macOS
/// (`swift test` on the CI runner has no iOS simulator attached) — the
/// platform font APIs are bridged via `NomiPlatformFont` for that reason.
public enum NomiFont {
  public static let montserratMedium = "Montserrat-Medium"
  public static let montserratSemiBold = "Montserrat-SemiBold"
  public static let montserratBold = "Montserrat-Bold"
  public static let interRegular = "Inter"

  /// One-time registration for the four bundled font files, in case the
  /// hosting app has not already registered them via `UIAppFonts`.
  public static func registerIfNeeded() {
    let names = [
      "Montserrat-Medium.otf",
      "Montserrat-SemiBold.otf",
      "Montserrat-Bold.otf",
      "Inter-Regular.otf",
    ]
    for name in names {
      guard let url = Bundle.module.url(forResource: name, withExtension: nil) else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}

/// Type roles mapped from DESIGN.md's Figma-derived scale, negative tracking preserved.
public enum NomiTextStyle {
  case dashboardHeroTotal
  case title
  case body
  case caption

  public var font: Font {
    switch self {
    case .dashboardHeroTotal: return .custom(NomiFont.montserratSemiBold, size: 39)
    case .title: return .custom(NomiFont.montserratSemiBold, size: 20)
    case .body: return .custom(NomiFont.montserratMedium, size: 16)
    case .caption: return .custom(NomiFont.interRegular, size: 13)
    }
  }
}

public extension View {
  func nomiTextStyle(_ style: NomiTextStyle) -> some View {
    font(style.font)
  }
}

/// Montserrat is wider than Inter at the same size, and `.monospacedDigit()`
/// is a system-font modifier that does not apply to a custom face. Reaching
/// Montserrat's `tnum` needs an explicit font descriptor with
/// `kNumberSpacingType`/`kMonospacedNumbersSelector` — written once, here.
public enum TabularFigures {
  public static func platformFont(name: String, size: CGFloat) -> NomiPlatformFont {
    #if canImport(UIKit)
    let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    let tabularFeature: [UIFontDescriptor.FeatureKey: Int] = [
      .featureIdentifier: kNumberSpacingType,
      .typeIdentifier: kMonospacedNumbersSelector,
    ]
    let descriptor = base.fontDescriptor.addingAttributes([
      .featureSettings: [tabularFeature],
    ])
    return UIFont(descriptor: descriptor, size: size)
    #elseif canImport(AppKit)
    let base = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    let tabularFeature: [NSFontDescriptor.FeatureKey: Int] = [
      .typeIdentifier: kNumberSpacingType,
      .selectorIdentifier: kMonospacedNumbersSelector,
    ]
    let descriptor = base.fontDescriptor.addingAttributes([
      .featureSettings: [tabularFeature],
    ])
    return NSFont(descriptor: descriptor, size: size) ?? base
    #endif
  }

  public static func font(name: String, size: CGFloat) -> Font {
    #if canImport(UIKit)
    Font(uiFont: platformFont(name: name, size: size))
    #elseif canImport(AppKit)
    Font(nsFont: platformFont(name: name, size: size))
    #endif
  }
}
