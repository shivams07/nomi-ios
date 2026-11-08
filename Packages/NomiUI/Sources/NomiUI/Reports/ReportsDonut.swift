import Foundation
import NomiCore
import SwiftUI

// clt-harness: include

/// The category donut on Insights (the approved artboard's 88 pt ring). Each
/// slice is an arc separated by a 2 degree gap, drawn from 12 o'clock
/// clockwise, with the top slice's share in the centre. The legend beside it
/// is the text alternative, so the ring itself is hidden from VoiceOver.
public struct ReportsDonut: View {
  public let slices: [CategorySlice]

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  static let diameter: CGFloat = 88
  static let ringWidth: CGFloat = 12
  static let gapDegrees: Double = 2

  /// Slice colours, darkest first. Built from `NomiColor` tokens only; the
  /// artboard's two lightest tints (#8DB3EA, #BBD3EE) are not tokens, so they
  /// are approximated as `blueMid` at lower opacity until F1 adds them.
  /// Index 7 is the grey used for the folded Other slice.
  static func color(at index: Int) -> Color {
    let ramp: [Color] = [
      NomiColor.navyDeep,
      NomiColor.blueMid,
      NomiColor.blueMid.opacity(0.6),
      NomiColor.navy,
      NomiColor.blueMid.opacity(0.4),
      NomiColor.blueMid.opacity(0.25),
      NomiColor.inkSecondary.opacity(0.5),
    ]
    return ramp.indices.contains(index) ? ramp[index] : NomiColor.inkSecondary.opacity(0.35)
  }

  /// Share of the total for each slice, as whole percent.
  static func percentages(_ slices: [CategorySlice]) -> [Int] {
    let total = slices.reduce(0) { $0 + $1.totalMinor }
    guard total > 0 else { return slices.map { _ in 0 } }
    return slices.map { Int((Double($0.totalMinor) / Double(total) * 100).rounded()) }
  }

  public var body: some View {
    let total = slices.reduce(0) { $0 + $1.totalMinor }
    let fractions = slices.map { total > 0 ? Double($0.totalMinor) / Double(total) : 0 }
    let arcs = ReportsDonutGeometry.arcs(fractions: fractions, gapDegrees: Self.gapDegrees)
    let topPercent = Self.percentages(slices).first ?? 0

    ZStack {
      Circle()
        .stroke(NomiColor.secondaryFill, lineWidth: Self.ringWidth)
      ForEach(Array(arcs.enumerated()), id: \.offset) { index, arc in
        Circle()
          .trim(from: arc.start / 360, to: arc.end / 360)
          .stroke(Self.color(at: index), style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
      if !arcs.isEmpty {
        VStack(spacing: 0) {
          Text("Top")
            .nomiTextStyle(.micro)
            .foregroundStyle(NomiColor.inkSecondary)
          Text("\(topPercent)%")
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.ink)
        }
      }
    }
    .padding(Self.ringWidth / 2)
    .frame(width: Self.diameter, height: Self.diameter)
    .accessibilityHidden(true)
  }
}

/// Arc geometry for `ReportsDonut`, separated from the view so the sweep can be
/// tested without drawing.
enum ReportsDonutGeometry {
  /// One arc per positive input, in degrees clockwise from 12 o'clock. The
  /// arcs share the circle's `360 - count * gapDegrees` sweep in proportion to
  /// their fractions, with `gapDegrees` between neighbours. Empty input, or
  /// input that sums to zero, gives no arcs.
  static func arcs(fractions: [Double], gapDegrees: Double) -> [(start: Double, end: Double)] {
    let positive = fractions.map { max($0, 0) }
    let sum = positive.reduce(0, +)
    guard !positive.isEmpty, sum > 0 else { return [] }

    let sweep = 360 - Double(positive.count) * gapDegrees
    var cursor = 0.0
    var arcs: [(start: Double, end: Double)] = []
    for fraction in positive {
      let length = fraction / sum * sweep
      arcs.append((start: cursor, end: cursor + length))
      cursor += length + gapDegrees
    }
    return arcs
  }
}
