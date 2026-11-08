import Foundation
import NomiCore
import Testing
@testable import NomiUI

// clt-harness: include

@Suite("Reports donut geometry")
struct ReportsDonutTests {
  private func sweep(_ arcs: [(start: Double, end: Double)]) -> Double {
    arcs.reduce(0) { $0 + ($1.end - $1.start) }
  }

  @Test func arcsSumToCircleLessOneGapPerSlice() {
    for count in 1...8 {
      let fractions = Array(repeating: 1.0 / Double(count), count: count)
      let arcs = ReportsDonutGeometry.arcs(fractions: fractions, gapDegrees: 2)
      #expect(arcs.count == count)
      #expect(abs(sweep(arcs) - (360 - Double(count) * 2)) < 0.01)
    }
  }

  @Test func arcsFollowTheArtboardSplit() {
    // Food 40%, Shopping 24%, Transport 16%, Other 20%, as on the Insights artboard.
    let arcs = ReportsDonutGeometry.arcs(fractions: [0.40, 0.24, 0.16, 0.20], gapDegrees: 2)
    #expect(arcs.count == 4)
    #expect(abs(arcs[0].start) < 0.01)
    #expect(abs((arcs[0].end - arcs[0].start) - 0.40 * 352) < 0.01)
    #expect(abs(arcs[1].start - (arcs[0].end + 2)) < 0.01)
    // The last arc stops one gap short of the start of the first: 360 - 2.
    #expect(abs(arcs[3].end - 358) < 0.01)
    #expect(abs(sweep(arcs) - 352) < 0.01)
  }

  @Test func emptyInputGivesNoArcs() {
    #expect(ReportsDonutGeometry.arcs(fractions: [], gapDegrees: 2).isEmpty)
    #expect(ReportsDonutGeometry.arcs(fractions: [0, 0], gapDegrees: 2).isEmpty)
  }

  @Test func singleSliceGivesOneArcLeavingOneGap() {
    let arcs = ReportsDonutGeometry.arcs(fractions: [1.0], gapDegrees: 2)
    #expect(arcs.count == 1)
    #expect(arcs[0].start == 0)
    #expect(abs(arcs[0].end - 358) < 0.01)
  }

  @Test func percentagesComeFromTotalsNotShares() {
    let slices = [
      CategorySlice(id: UUID(), name: "A", paletteSlot: 0, totalMinor: 400, share: 0),
      CategorySlice(id: UUID(), name: "B", paletteSlot: 1, totalMinor: 600, share: 0),
    ]
    #expect(ReportsDonut.percentages(slices) == [40, 60])
    #expect(ReportsDonut.percentages([]) == [])
  }
}
