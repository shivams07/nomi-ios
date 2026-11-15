// clt-harness: include
import CoreGraphics

/// Strict 8pt scale: 4, 8, 16, 24, 32, 40, 48, with 4 as the only half-step.
/// Layout values follow I-2 of nomi-ios-build-plan, except the screen gutter,
/// which is 16 under Moss (plan I-9; it was 20 on every earlier artboard).
public enum NomiSpacing {
  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 16
  public static let md: CGFloat = 24
  public static let lg: CGFloat = 32
  public static let xl: CGFloat = 40
  public static let xxl: CGFloat = 48

  /// Screen side gutter (was 20, and `md` before that).
  public static let screenGutter: CGFloat = 16
  public static let cardPadding = sm
  public static let cardToCard = sm
  public static let sectionGap = lg

  public static let tabBarSideMargin: CGFloat = 24
  public static let tabBarBottomMargin: CGFloat = 22
  /// Smallest tappable size.
  public static let minTarget: CGFloat = 44
  public static let navRowHeight: CGFloat = 44
  public static let cardGap: CGFloat = 12
  /// How far a sheet overlaps the hero above it.
  public static let heroSheetOverlap: CGFloat = 24
  public static let rowMinHeight: CGFloat = 52
}
