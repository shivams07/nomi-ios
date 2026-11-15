import SwiftUI

// clt-harness: include

/// The bottom margin a tab root's main vertical scroll view adds (F3b, I-15), so its
/// last row clears the floating bar by 12 pt. Pushed screens and sheets get 0 from
/// `RootView`, because the bar is hidden there.
public enum NomiTabBarReserve {
  /// The margin for a bar of `barHeight`, on a device whose bottom safe area is
  /// `safeAreaBottom`. The scroll view already starts at the safe-area edge, so the
  /// safe area is taken off the bar's full distance above the physical bottom.
  public static func margin(barHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
    max(0, barHeight + NomiTabBarMetrics.bottomOffset + 12 - safeAreaBottom)
  }
}

private struct NomiTabBarReserveKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
  /// The bottom reserve for the current screen. 0 unless a tab root sets it.
  var nomiTabBarReserve: CGFloat {
    get { self[NomiTabBarReserveKey.self] }
    set { self[NomiTabBarReserveKey.self] = newValue }
  }
}
