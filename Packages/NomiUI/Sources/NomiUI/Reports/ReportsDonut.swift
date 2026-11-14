import Foundation
import NomiCore
import SwiftUI

// clt-harness: include

/// The category donut on Insights (the approved artboard's 88 pt ring). Each
/// slice is an arc separated by a 2 degree gap, drawn from 12 o'clock
/// clockwise, with the top slice's share in the centre. The legend beside it
/// is the text alternative, so the ring itself is hidden from VoiceOver.
///
/// The ring takes the output of `displaySlices`, so it never shows more than
/// four slices (decisions Amendment 2, R3).
public struct ReportsDonut: View {
  public let slices: [CategorySlice]

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  static let diameter: CGFloat = 88
  static let ringWidth: CGFloat = 12
  static let gapDegrees: Double = 2

  /// The most slices the ring and legend show.
  static let maxDisplayedSlices = 4

  /// Stable identity for the folded "Other" slice on the ring and legend. A
  /// separate constant from `ReportsCategoryFold.otherOverflowID`, which is
  /// not touched by this unit.
  static let displayOtherID = UUID(uuidString: "00000000-0000-0000-0000-0000000000fd")!

  /// Slice fills in artboard order: navyDeep, blueMid, chartTintMid,
  /// chartTintLight. Four stops only, because `displaySlices` caps the count.
  static func color(at index: Int) -> Color {
    switch index {
    case 0: return NomiColor.navyDeep
    case 1: return NomiColor.blueMid
    case 2: return NomiColor.chartTintMid
    default: return NomiColor.chartTintLight
    }
  }

  /// The slices the ring and legend show. Up to four are returned as given.
  /// From five, the top three by total are kept, then one "Other" holding the
  /// exact sum of the rest, so the shown totals always sum to the input total.
  static func displaySlices(_ slices: [CategorySlice]) -> [CategorySlice] {
    guard slices.count > maxDisplayedSlices else { return slices }
    let sorted = slices.sorted { $0.totalMinor > $1.totalMinor }
    let top = Array(sorted.prefix(maxDisplayedSlices - 1))
    let rest = sorted.dropFirst(maxDisplayedSlices - 1)
    let other = CategorySlice(
      id: displayOtherID,
      name: "Other",
      paletteSlot: -1,
      totalMinor: rest.reduce(0) { $0 + $1.totalMinor },
      share: rest.reduce(0.0) { $0 + $1.share }
    )
    return top + [other]
  }

  /// Share of the total for each slice, as whole percent, from the slices as
  /// passed (the caller passes the displayed slices).
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
