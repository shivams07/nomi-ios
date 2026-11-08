// clt-harness: include
import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias NomiPlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias NomiPlatformFont = NSFont
#endif

/// Inter only (nomi-ios-build-plan, I-3). Montserrat is gone: no files, names
/// or aliases.
///
/// Font files ship in `Resources/Fonts/**` as package resources, not app
/// resources. `UIAppFonts` only covers fonts in the *app* bundle, so
/// `App/Info.plist` does not declare them (U18). `registerIfNeeded` below is
/// the only thing that puts these on the process font table.
///
/// Inter Medium and Inter SemiBold ship beside Regular under DEC-02 (F2F), all
/// three from one Inter 4.1 release. Add font files here only under DEC-02.
///
/// This file targets iOS at runtime but also compiles under plain macOS
/// (`swift test` on the CI runner has no iOS simulator attached). The platform
/// font APIs are bridged via `NomiPlatformFont` for that reason.
public enum NomiFont {
  public static let interRegular = "Inter-Regular"
  public static let interMedium = "Inter-Medium"
  public static let interSemiBold = "Inter-SemiBold"

  /// Font files present in `Resources/Fonts`: Inter Regular, Medium and SemiBold (F2F).
  public static let bundledFileNames: [String] = [
    "Inter-Regular.otf",
    "Inter-Medium.otf",
    "Inter-SemiBold.otf",
  ]

  /// One-time registration for every file in `bundledFileNames`. See the type
  /// doc above for why nothing else registers them.
  public static func registerIfNeeded() {
    for name in bundledFileNames {
      guard let url = Bundle.module.url(forResource: name, withExtension: nil) else { continue }
      var registrationError: Unmanaged<CFError>?
      let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
      guard !didRegister else { continue }
      // A second call in the same process re-registers nothing already
      // registered. `didRegister` is false, but the font resolves by name
      // just fine, so that's a repeat call, not a failure.
      let postScriptName = name.hasSuffix(".otf") ? String(name.dropLast(4)) : name
      let alreadyResolves = NomiPlatformFont(name: postScriptName, size: 12) != nil
      assert(alreadyResolves, "Failed to register \(name): \(String(describing: registrationError))")
    }
  }
}

/// Type roles from the approved light system (I-3). Negative tracking is kept where
/// the artboards set it.
public enum NomiTextStyle {
  /// Large title (H0 nav bar, via the appearance proxy): SemiBold 34, tracking -0.4.
  case largeTitle
  /// Hero amount: Regular 48, tracking -1.4.
  case heroAmount
  /// Accounts hero title: SemiBold 24.
  case heroTitle
  /// Gauge centre, sheet amount. Regular 28, tracking -0.6. Remapped.
  case displayValue
  /// Insights headline totals (Spent, Received): Regular 24, tracking -0.4.
  /// Added by IN (decisions Amendment 2 R2). `displayValue` is unchanged.
  case summaryValue
  /// Section and card titles. SemiBold 20. Remapped.
  case title
  /// Card titles and sheet titles: SemiBold 17.
  case headline
  /// Body text. Medium 16. Remapped.
  case body
  /// Merchant and row labels: Medium 15.
  case rowTitle
  /// Settings rows: Regular 15.
  case rowBody
  /// Row amounts: Medium 16, monospaced digits.
  case amount
  /// Credit amounts: SemiBold 16, monospaced digits.
  case amountStrong
  /// The black pill button: SemiBold 16.
  case button
  /// Cancel: Medium 17.
  case navAction
  /// Save: SemiBold 17.
  case navActionStrong
  /// Filter chips: Medium 14.
  case chip
  /// The selected filter chip: SemiBold 14.
  case chipSelected
  /// Hero label row: Medium 13.
  case subhead
  /// Read-only chip on a hero: Medium 12.
  case heroChip
  /// Section labels: SemiBold 13.
  case label
  /// Small body text: Regular 13. Kept unchanged.
  case caption
  /// Row subtitles and card captions: Regular 12.
  case footnote
  /// Chart ticks: Medium 11.
  case micro
  /// Tab bar labels: Medium 10.5.
  case tabLabel

  public var font: Font {
    switch self {
    case .largeTitle: return .custom(NomiFont.interSemiBold, size: 34, relativeTo: .largeTitle)
    case .heroAmount: return .custom(NomiFont.interRegular, size: 48, relativeTo: .largeTitle)
    case .heroTitle: return .custom(NomiFont.interSemiBold, size: 24, relativeTo: .title)
    case .displayValue: return .custom(NomiFont.interRegular, size: 28, relativeTo: .title)
    case .summaryValue: return .custom(NomiFont.interRegular, size: 24, relativeTo: .title2)
    case .title: return .custom(NomiFont.interSemiBold, size: 20, relativeTo: .title3)
    case .headline: return .custom(NomiFont.interSemiBold, size: 17, relativeTo: .headline)
    case .body: return .custom(NomiFont.interMedium, size: 16, relativeTo: .body)
    case .rowTitle: return .custom(NomiFont.interMedium, size: 15, relativeTo: .body)
    case .rowBody: return .custom(NomiFont.interRegular, size: 15, relativeTo: .body)
    case .amount: return .custom(NomiFont.interMedium, size: 16, relativeTo: .body).monospacedDigit()
    case .amountStrong: return .custom(NomiFont.interSemiBold, size: 16, relativeTo: .body).monospacedDigit()
    case .button: return .custom(NomiFont.interSemiBold, size: 16, relativeTo: .body)
    case .navAction: return .custom(NomiFont.interMedium, size: 17, relativeTo: .body)
    case .navActionStrong: return .custom(NomiFont.interSemiBold, size: 17, relativeTo: .body)
    case .chip: return .custom(NomiFont.interMedium, size: 14, relativeTo: .subheadline)
    case .chipSelected: return .custom(NomiFont.interSemiBold, size: 14, relativeTo: .subheadline)
    case .subhead: return .custom(NomiFont.interMedium, size: 13, relativeTo: .subheadline)
    case .heroChip: return .custom(NomiFont.interMedium, size: 12, relativeTo: .caption)
    case .label: return .custom(NomiFont.interSemiBold, size: 13, relativeTo: .footnote)
    case .caption: return .custom(NomiFont.interRegular, size: 13, relativeTo: .caption)
    case .footnote: return .custom(NomiFont.interRegular, size: 12, relativeTo: .caption)
    case .micro: return .custom(NomiFont.interMedium, size: 11, relativeTo: .caption2)
    case .tabLabel: return .custom(NomiFont.interMedium, size: 10.5, relativeTo: .caption2)
    }
  }

  public var tracking: CGFloat {
    switch self {
    case .largeTitle: return -0.4
    case .heroAmount: return -1.4
    case .displayValue: return -0.6
    case .summaryValue: return -0.4
    default: return 0
    }
  }
}

public extension View {
  func nomiTextStyle(_ style: NomiTextStyle) -> some View {
    font(style.font).tracking(style.tracking)
  }
}

/// `.monospacedDigit()` is a system-font modifier and does not apply to a custom
/// face. Inter's tabular figures need an explicit font descriptor with
/// `kNumberSpacingType`/`kMonospacedNumbersSelector`, written once, here.
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
    Font(platformFont(name: name, size: size) as UIFont)
    #elseif canImport(AppKit)
    Font(platformFont(name: name, size: size) as NSFont)
    #endif
  }
}
