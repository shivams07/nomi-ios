import CoreGraphics
import SwiftUI

/// Radius scale — 8 tiles, 16 inset, 24 cards/bars/nav/sheets, full pill for
/// buttons/chips/avatars. Nothing below 8, one flagged exception: chart bar
/// caps at 4pt (declared in `NomiChart`-adjacent code, not here — the floor
/// this type expresses is the one every surface, control, chip and sheet obeys).
/// v5 (`nomi-ui-refresh`): `card` 16 → 24, restoring the v4 ruling that
/// never shipped. Concentric rule: card 24 → inset 16 → tile 8.
public enum NomiRadius {
  public static let tile: CGFloat = 8
  /// v5, new: tiles inside a card (hero Income/Expenses), ledger row cards,
  /// subscription row cards, per-category budget cards.
  public static let inset: CGFloat = 16
  public static let card: CGFloat = 24
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
