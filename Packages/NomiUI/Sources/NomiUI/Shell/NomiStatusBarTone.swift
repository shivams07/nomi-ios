import SwiftUI

// clt-harness: include

/// The status bar glyph colour a screen needs (SB1, nomi-ios-statusbar-ruling).
/// `dark` is dark glyphs over a light ground; `light` is light glyphs over the
/// navy hero.
public enum NomiStatusBarTone: String, Equatable, Sendable {
  /// The content behind the status bar is light: dark glyphs.
  case dark
  /// The content behind the status bar is the navy hero: light glyphs.
  case light
}

/// The pure rule behind `NomiStatusBarToneKey`. NomiUI decides the tone; NomiApp
/// only asks `showsLightOverlay` and never computes a tone itself.
public enum NomiStatusBarToneRule {
  /// `nil` when the hero is not on screen (pushed over, tab switched away).
  /// Otherwise `.light` if and only if the hero gradient covers the vertical
  /// midpoint of the status-bar band, where the band's midpoint is
  /// `safeTop / 2`: `heroMinY <= mid && heroMaxY - overlap >= mid`. Else `.dark`.
  /// `heroMaxY - overlap` is the visible bottom, because the sheet rises
  /// `overlap` points into the hero block.
  public static func tone(
    isOnScreen: Bool,
    heroMinY: CGFloat,
    heroMaxY: CGFloat,
    overlap: CGFloat,
    safeTop: CGFloat
  ) -> NomiStatusBarTone? {
    guard isOnScreen else { return nil }
    let mid = safeTop / 2
    return (heroMinY <= mid && heroMaxY - overlap >= mid) ? .light : .dark
  }

  /// Preference reduction: `.light` if either side is `.light`, else the first
  /// non-nil value.
  public static func combine(_ a: NomiStatusBarTone?, _ b: NomiStatusBarTone?) -> NomiStatusBarTone? {
    if a == .light || b == .light { return .light }
    return a ?? b
  }

  /// The one question NomiApp asks: should the light overlay be shown?
  public static func showsLightOverlay(_ tone: NomiStatusBarTone?) -> Bool {
    tone == .light
  }
}

/// Publishes the status bar tone of the hero currently under the status bar.
/// `NomiHeroScaffold` sets it; nothing reads it in NomiUI.
public struct NomiStatusBarToneKey: PreferenceKey {
  public static let defaultValue: NomiStatusBarTone? = nil

  public static func reduce(value: inout NomiStatusBarTone?, nextValue: () -> NomiStatusBarTone?) {
    value = NomiStatusBarToneRule.combine(value, nextValue())
  }
}
