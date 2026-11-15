import CoreGraphics

// clt-harness: include

/// Which slot a touch in the tab bar lands on (F3c, I-16 Amendment 1). The UIKit touch
/// overlay asks this for every touch, so a hold, a slide and a tap all resolve through
/// the same geometry as `NomiTabBarMetrics`. Pure, so `NomiTabBarHitTests` pins it.
public enum NomiTabBarHit {
  /// The five slots, the `+` third: two tabs, the `+`, two tabs.
  public static let slotCount = 5

  /// Slot index 0...4 (the `+` is 2) for a point `x` in the bar's own coordinates, or nil
  /// outside the bar. Inside the padding or a gap, the nearest slot by distance to its
  /// centre. An exact tie goes to the lower index, so a point in the middle of a gap
  /// selects the slot on its left, as UITabBar does.
  public static func slot(atX x: CGFloat, barWidth: CGFloat = NomiTabBarMetrics.barWidth) -> Int? {
    guard x >= 0, x <= barWidth else { return nil }
    var best = 0
    var bestDistance = abs(x - centreX(of: 0))
    for index in 1..<slotCount {
      let distance = abs(x - centreX(of: index))
      if distance < bestDistance {
        best = index
        bestDistance = distance
      }
    }
    return best
  }

  /// Centre x of slot `index`: padding + slot / 2 + index * (slot + gap).
  public static func centreX(of index: Int) -> CGFloat {
    NomiTabBarMetrics.padding
      + NomiTabBarMetrics.slot / 2
      + CGFloat(index) * (NomiTabBarMetrics.slot + NomiTabBarMetrics.gap)
  }
}
