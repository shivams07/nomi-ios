// clt-harness: include
import Foundation

/// WCAG 2.x relative luminance, contrast ratio and alpha blending on `NomiHex`
/// integers. Pure arithmetic: the token gates run without rendering, and the
/// decimal rule (SIMP §1 rule 4) is checked by blending the ink over the ground.
public enum NomiContrast {
  /// Relative luminance of an sRGB hex colour, 0...1 (WCAG 2.x, 0.03928 threshold).
  public static func relativeLuminance(_ hex: UInt32) -> Double {
    let red = linear(Double((hex >> 16) & 0xFF) / 255)
    let green = linear(Double((hex >> 8) & 0xFF) / 255)
    let blue = linear(Double(hex & 0xFF) / 255)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  /// Contrast ratio between two colours, 1...21.
  public static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
    let lighter = max(relativeLuminance(first), relativeLuminance(second))
    let darker = min(relativeLuminance(first), relativeLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// `foreground` at `alpha` composited over `background` in sRGB, each channel
  /// rounded to the nearest integer (the way the artboards' opacity is drawn).
  public static func blend(_ foreground: UInt32, over background: UInt32, alpha: Double) -> UInt32 {
    let clamped = min(max(alpha, 0), 1)
    func channel(_ shift: UInt32) -> UInt32 {
      let fore = Double((foreground >> shift) & 0xFF)
      let back = Double((background >> shift) & 0xFF)
      return UInt32((fore * clamped + back * (1 - clamped)).rounded())
    }
    return (channel(16) << 16) | (channel(8) << 8) | channel(0)
  }

  private static func linear(_ channel: Double) -> Double {
    channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
  }
}
