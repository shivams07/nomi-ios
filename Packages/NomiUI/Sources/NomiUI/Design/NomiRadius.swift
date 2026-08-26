import CoreGraphics
import SwiftUI

/// Radius scale — 8 tiles, 16 cards, 24 bars/nav/sheets, full pill for
/// buttons/chips/avatars. Nothing below 8, one flagged exception: chart bar
/// caps at 4pt (declared in `NomiChart`-adjacent code, not here — the floor
/// this type expresses is the one every surface, control, chip and sheet obeys).
public enum NomiRadius {
  public static let tile: CGFloat = 8
  public static let card: CGFloat = 16
  public static let bar: CGFloat = 24
  public static let pill: CGFloat = .infinity

  /// Cards and sheets round at 24, `.continuous`, per the design doc.
  public static let cardSheetStyle: RoundedCornerStyle = .continuous
}

public extension View {
  func nomiCornerRadius(_ radius: CGFloat, style: RoundedCornerStyle = .continuous) -> some View {
    clipShape(RoundedRectangle(cornerRadius: radius, style: style))
  }
}
