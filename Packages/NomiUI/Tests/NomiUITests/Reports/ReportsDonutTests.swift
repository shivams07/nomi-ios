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

  private func slices(_ totals: [Int]) -> [CategorySlice] {
    totals.enumerated().map { index, total in
      CategorySlice(id: UUID(), name: "C\(index)", paletteSlot: index, totalMinor: total, share: 0)
    }
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
    let input = slices([400, 600])
    #expect(ReportsDonut.percentages(input) == [40, 60])
    #expect(ReportsDonut.percentages([]) == [])
  }

  // MARK: - Slice colours (decisions Amendment 2, R3)

  @Test func sliceColoursFollowArtboardOrder() {
    #expect(ReportsDonut.color(at: 0) == NomiColor.navyDeep)
    #expect(ReportsDonut.color(at: 1) == NomiColor.blueMid)
    #expect(ReportsDonut.color(at: 2) == NomiColor.chartTintMid)
    #expect(ReportsDonut.color(at: 3) == NomiColor.chartTintLight)
  }

  // MARK: - Display fold (decisions Amendment 2, A-19.4)

  @Test func displayFoldIsIdentityUpToFourSlices() {
    for count in 0...4 {
      let input = slices(Array(repeating: 100, count: count))
      #expect(ReportsDonut.displaySlices(input).map(\.id) == input.map(\.id))
    }
  }

  @Test func displayedTotalsSumExactlyToTheInputTotal() {
    for count in [4, 5, 11] {
      let input = slices((0..<count).map { ($0 * 37 + 11) * 100 + $0 })
      let shown = ReportsDonut.displaySlices(input)
      #expect(shown.count == min(count, 4))
      #expect(shown.reduce(0) { $0 + $1.totalMinor } == input.reduce(0) { $0 + $1.totalMinor })
    }
  }

  @Test func fromFiveSlicesTheTopThreePlusOtherHoldsTheRemainder() {
    let input = slices([500, 3000, 1000, 500, 200])
    let shown = ReportsDonut.displaySlices(input)
    #expect(shown.map(\.totalMinor) == [3000, 1000, 500, 700])
    #expect(shown.last?.name == "Other")
    #expect(shown.last?.id == ReportsDonut.displayOtherID)
  }

  @Test func legendPercentagesComeFromDisplayedTotals() {
    // Top three 5000, 3000, 1000; the two 500s fold to Other at 1000. Total 10000.
    let input = slices([5000, 3000, 1000, 500, 500])
    let shown = ReportsDonut.displaySlices(input)
    #expect(shown.map(\.totalMinor) == [5000, 3000, 1000, 1000])
    #expect(ReportsDonut.percentages(shown) == [50, 30, 10, 10])
  }

  // MARK: - Muted bars (decisions Amendment 2, A-19.5)

  @Test func mutedBarsClearThreeToOneOnCardAndAgainstHighlight() {
    // Solid chartMuted (blueMid) and chartHighlight (navyDeep), no alpha: 3.71 and 3.64.
    #expect(NomiContrast.ratio(NomiHex.blueMid, NomiHex.card) >= 3.0)
    #expect(NomiContrast.ratio(NomiHex.blueMid, NomiHex.navyDeep) >= 3.0)
  }
}
