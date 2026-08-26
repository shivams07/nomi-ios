import Foundation
import Testing
@testable import NomiCore

struct TypesTests {
  @Test func insightPeriodIsHashableForMonthCase() {
    var set: Set<InsightPeriod> = []
    set.insert(.month(year: 2026, month: 4))
    set.insert(.month(year: 2026, month: 4))
    set.insert(.month(year: 2026, month: 5))
    #expect(set.count == 2)
  }

  @Test func insightPeriodDistinguishesFinancialYearFromMonth() {
    #expect(InsightPeriod.financialYear(startingYear: 2026) != InsightPeriod.month(year: 2026, month: 4))
  }

  @Test func directionStrategyEncodesAndDecodes() throws {
    let strategy = DirectionStrategy.separateColumns(debit: 3, credit: 4)
    let data = try JSONEncoder().encode(strategy)
    let decoded = try JSONDecoder().decode(DirectionStrategy.self, from: data)
    #expect(decoded == strategy)
  }
}
