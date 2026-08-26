import CoreGraphics

/// Strict 8pt scale — 4, 8, 16, 24, 32, 40, 48 — with 4 as the only half-step.
/// Screen gutter 24, card padding 16, card-to-card 16, section gap 32.
public enum NomiSpacing {
  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 16
  public static let md: CGFloat = 24
  public static let lg: CGFloat = 32
  public static let xl: CGFloat = 40
  public static let xxl: CGFloat = 48

  public static let screenGutter = md
  public static let cardPadding = sm
  public static let cardToCard = sm
  public static let sectionGap = lg
}
