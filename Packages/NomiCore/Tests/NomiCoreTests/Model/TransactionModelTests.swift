import Foundation
import Testing
@testable import NomiCore

struct TransactionModelTests {
  @Test func directionComputedPropertyRoundTrips() {
    let transaction = Transaction()
    transaction.direction = .credit
    #expect(transaction.directionRaw == "credit")
    #expect(transaction.direction == .credit)
  }

  @Test func categorySourceComputedPropertyRoundTrips() {
    let transaction = Transaction()
    transaction.categorySource = .manual
    #expect(transaction.categorySourceRaw == "manual")
  }

  @Test func everyModelPropertyHasADefault() {
    let transaction = Transaction()
    #expect(transaction.descriptionText == "")
    #expect(transaction.amountMinor == 0)
    #expect(transaction.currencyCode == "INR")
    #expect(transaction.mergedCount == 1)
    #expect(transaction.needsReview == false)

    let category = Category()
    #expect(category.name == "")
    #expect(category.paletteSlot == 0)

    let budget = Budget()
    #expect(budget.amountMinor == 0)
    #expect(budget.isEnabled == true)

    let rule = Rule()
    #expect(rule.pattern == "")
    #expect(rule.priority == 0)

    let account = Account()
    #expect(account.kindRaw == "bank")
    #expect(account.isArchived == false)
  }
}
