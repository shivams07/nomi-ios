import SwiftUI

// clt-harness: include

/// One colour stop of a hero gradient: `location` runs 0 (top) to 1 (bottom).
public struct NomiHeroStop: Equatable, Sendable {
  public let location: Double
  public let hex: UInt32
}

/// The hero gradient ramp (F3 of nomi-ios-build-plan, I-4; SIMP §1). The ramp
/// is authored in artboard points at a 54 pt safe-area top. `stops` moves it to
/// the device's safe area and to the hero's measured height.
public enum NomiHeroGradient {
  /// The safe-area top the artboards were drawn at.
  public static let artboardSafeTop: CGFloat = 54

  /// Artboard points (y) where white hero text stops passing 4.5:1. White is
  /// at or above 4.5:1 through y 299 and below it from y 300 (Moss ramp, plan
  /// I-9 and Risks 1). Text may sit at or above this line.
  public static let whiteTextFloor: CGFloat = 299

  /// Artboard points (y) from which moss900 text passes 4.5:1 on the ramp.
  /// It is at or above 4.5:1 from y 361 and below it at y 360. Text in the
  /// band between `whiteTextFloor` and this value fails both colours.
  public static let darkTextCeiling: CGFloat = 361

  /// Artboard (y, hex) for the Moss Home hero (504 pt tall): heroRamp0 at 0,
  /// heroRamp1 at 171, heroRamp2 at 313, heroRamp3 at 434, heroRamp4 at 504.
  public static let ramp: [(y: CGFloat, hex: UInt32)] = [
    (0, NomiHex.heroRamp0),
    (171, NomiHex.heroRamp1),
    (313, NomiHex.heroRamp2),
    (434, NomiHex.heroRamp3),
    (504, NomiHex.heroRamp4),
  ]

  /// Backfill's moment gradient: heroRamp0 at 0, heroRamp1 at 0.45, heroRamp2
  /// at 1.0 (canvas Backfill board).
  static let momentStops: [NomiHeroStop] = [
    NomiHeroStop(location: 0, hex: NomiHex.heroRamp0),
    NomiHeroStop(location: 0.45, hex: NomiHex.heroRamp1),
    NomiHeroStop(location: 1.0, hex: NomiHex.heroRamp2),
  ]

  /// Stops for a hero `height` points tall, measured from the top of the screen.
  ///
  /// Every ramp point except y 0 moves by `safeTop - 54`. Points at or past
  /// `height` are dropped, and the colour at `height` is appended as the last
  /// stop at location 1.
  public static func stops(height: CGFloat, safeTop: CGFloat) -> [NomiHeroStop] {
    guard height > 0 else { return [] }
    let shift = safeTop - artboardSafeTop
    let points: [(y: CGFloat, hex: UInt32)] = ramp.map { point in
      (y: point.y == 0 ? 0 : point.y + shift, hex: point.hex)
    }
    var result = points
      .filter { $0.y < height }
      .map { NomiHeroStop(location: Double($0.y / height), hex: $0.hex) }
    result.append(NomiHeroStop(location: 1, hex: hex(at: height, in: points)))
    return result
  }

  /// The hero gradient for `height`, drawn top to bottom.
  public static func gradient(height: CGFloat, safeTop: CGFloat) -> LinearGradient {
    let computed = stops(height: height, safeTop: safeTop)
    guard !computed.isEmpty else {
      return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
    }
    return LinearGradient(
      stops: computed.map { Gradient.Stop(color: Color(hex: $0.hex), location: $0.location) },
      startPoint: .top,
      endPoint: .bottom
    )
  }

  /// Backfill's gradient, drawn over the full 844 pt artboard height.
  public static let moment = LinearGradient(
    stops: momentStops.map { Gradient.Stop(color: Color(hex: $0.hex), location: $0.location) },
    startPoint: .top,
    endPoint: .bottom
  )

  /// The moment gradient's colour at `fraction` of its height, 0...1.
  /// Tests use it to check contrast on the Backfill background.
  static func momentHex(atFraction fraction: CGFloat) -> UInt32 {
    let stops = momentStops
    let clamped = Double(min(max(fraction, 0), 1))
    for (lower, upper) in zip(stops, stops.dropFirst()) where clamped <= upper.location {
      let span = upper.location - lower.location
      let t = span > 0 ? (clamped - lower.location) / span : 0
      return mix(lower.hex, upper.hex, CGFloat(t))
    }
    return stops[stops.count - 1].hex
  }

  // MARK: - Private

  /// Colour at `y` on the piecewise-linear ramp. Above the last point, the
  /// last colour holds.
  private static func hex(at y: CGFloat, in points: [(y: CGFloat, hex: UInt32)]) -> UInt32 {
    guard let lower = points.last(where: { $0.y <= y }) else { return points[0].hex }
    guard let upper = points.first(where: { $0.y > y }) else { return lower.hex }
    return mix(lower.hex, upper.hex, (y - lower.y) / (upper.y - lower.y))
  }

  /// Per-channel linear interpolation, each channel rounded to the nearest integer.
  private static func mix(_ from: UInt32, _ to: UInt32, _ t: CGFloat) -> UInt32 {
    var result: UInt32 = 0
    for shift in [16, 8, 0] as [UInt32] {
      let start = CGFloat((from >> shift) & 0xFF)
      let end = CGFloat((to >> shift) & 0xFF)
      let channel = UInt32((start + (end - start) * t).rounded())
      result |= channel << shift
    }
    return result
  }
}
