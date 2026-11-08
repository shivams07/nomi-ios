import Testing
@testable import NomiUI

// clt-harness: include

/// Pure query rules for the Ledger search box (D2). The screen's own search
/// path, and the contract's match rules against the real store, are covered
/// elsewhere: `APPT/TransactionSearchTests.swift` for the store, and V3 for
/// the screen.
struct LedgerSearchTests {
  @Test func blankIsNil() {
    #expect(LedgerSearch.normalized("") == nil)
    #expect(LedgerSearch.normalized("   ") == nil)
    #expect(LedgerSearch.normalized("\n\t") == nil)
  }

  @Test func trimsEdges() {
    #expect(LedgerSearch.normalized("  swig ") == "swig")
    #expect(LedgerSearch.normalized("\nswig\t") == "swig")
  }

  @Test func keepsInnerSpaces() {
    #expect(LedgerSearch.normalized("acme payroll") == "acme payroll")
  }

  @Test func limitIs200() {
    #expect(LedgerSearch.limit == 200)
  }
}
