import Testing
@testable import NomiUI

// clt-harness: include

/// The line break behind the entry sheet's wrapping chip row (EN). Pure: no
/// view is built, so the rule is checked on widths alone.
@Suite struct EntryChipFlowLayoutTests {
  @Test func threeChipsFittingOneLineStayOnOneLine() {
    // 50 + 8 + 50 + 8 + 50 = 166, within 200.
    #expect(EntryChipFlow.lines(widths: [50, 50, 50], available: 200, spacing: 8) == [[0, 1, 2]])
  }

  @Test func thirdChipWrapsWhenItWouldOverflow() {
    // 100 + 8 + 100 = 208 fits in 220; adding a third 100 needs 316.
    #expect(EntryChipFlow.lines(widths: [100, 100, 100], available: 220, spacing: 8) == [[0, 1], [2]])
  }

  @Test func oversizeChipSitsAloneOnItsLine() {
    // The 300-wide chip is wider than 200 on its own, so it neither joins
    // a neighbour nor gets truncated.
    #expect(EntryChipFlow.lines(widths: [50, 300, 50], available: 200, spacing: 8) == [[0], [1], [2]])
  }

  @Test func noChipsGivesNoLines() {
    #expect(EntryChipFlow.lines(widths: [], available: 200, spacing: 8) == [])
  }
}
