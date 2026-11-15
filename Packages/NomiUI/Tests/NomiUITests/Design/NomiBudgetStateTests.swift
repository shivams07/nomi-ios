// clt-harness: include
import Testing
@testable import NomiUI

/// NomiBudgetState (F2a, I-17). Integer maths only: the edges are 90% (close,
/// inclusive) and 100% (over, inclusive), and a budget of zero or less is never
/// close or over.
@Suite("Budget state")
struct NomiBudgetStateTests {
  @Test func emptyBudgetIsUnder() {
    #expect(NomiBudgetState.of(spentMinor: 0, budgetMinor: 0) == .under)
    #expect(NomiBudgetState.of(spentMinor: 1, budgetMinor: 0) == .under)
    #expect(NomiBudgetState.of(spentMinor: 1, budgetMinor: -100) == .under)
  }

  @Test func justBelowNinetyPercentIsUnder() {
    #expect(NomiBudgetState.of(spentMinor: 899, budgetMinor: 1000) == .under)
    #expect(NomiBudgetState.of(spentMinor: 0, budgetMinor: 1000) == .under)
  }

  @Test func ninetyPercentToJustUnderBudgetIsClose() {
    #expect(NomiBudgetState.of(spentMinor: 900, budgetMinor: 1000) == .close)
    #expect(NomiBudgetState.of(spentMinor: 999, budgetMinor: 1000) == .close)
  }

  @Test func atAndAboveBudgetIsOver() {
    #expect(NomiBudgetState.of(spentMinor: 1000, budgetMinor: 1000) == .over)
    #expect(NomiBudgetState.of(spentMinor: 1001, budgetMinor: 1000) == .over)
    #expect(NomiBudgetState.of(spentMinor: 1_40_000_00, budgetMinor: 1_00_000_00) == .over)
  }

  @Test func paiseAreCountedExactly() {
    // 90% of 1 rupee is 90 paise: 89 paise is under, 90 is close.
    #expect(NomiBudgetState.of(spentMinor: 89, budgetMinor: 100) == .under)
    #expect(NomiBudgetState.of(spentMinor: 90, budgetMinor: 100) == .close)
  }

  @Test func tagTextPerState() {
    #expect(NomiBudgetState.under.tagText == nil)
    #expect(NomiBudgetState.close.tagText == "Close")
    #expect(NomiBudgetState.over.tagText == "Over")
    #expect(NomiBudgetState.of(spentMinor: 0, budgetMinor: 1000).tagText == nil)
    #expect(NomiBudgetState.of(spentMinor: 950, budgetMinor: 1000).tagText == "Close")
    #expect(NomiBudgetState.of(spentMinor: 1200, budgetMinor: 1000).tagText == "Over")
  }
}
