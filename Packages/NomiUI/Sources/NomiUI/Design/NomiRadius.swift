// clt-harness: include
import CoreGraphics
import SwiftUI

/// Radius scale (F1 of nomi-ios-build-plan, I-2): tile 8, inset 16, card 24,
/// sheet 32, chip 18 (a 36-high chip), control 22 (a 44-high pill), and a full
/// pill. Concentric rule: card 24 -> inset 16 -> tile 8.
public enum NomiRadius {
  public static let tile: CGFloat = 8
  /// Tiles inside a card: hero Income and Expenses, ledger row cards,
  /// subscription row cards, per-category budget cards.
  public static let inset: CGFloat = 16
  public static let card: CGFloat = 24
  /// Sheets, from the light restyle (presented by `nomiSheet`).
  public static let sheet: CGFloat = 32
  /// A 36-high chip.
  public static let chip: CGFloat = 18
  /// A 44-high pill control.
  public static let control: CGFloat = 22

  public static let pill: CGFloat = .infinity

  /// Cards and sheets round `.continuous`, per the design doc.
  public static let cardSheetStyle: RoundedCornerStyle = .continuous
}

public extension View {
  func nomiCornerRadius(_ radius: CGFloat, style: RoundedCornerStyle = .continuous) -> some View {
    clipShape(RoundedRectangle(cornerRadius: radius, style: style))
  }
}
