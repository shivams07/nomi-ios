import Foundation
import Testing

@testable import NomiCore

/// Every case here is stated in the design's U10 acceptance criteria. The
/// evaluator is pure, so these need no container, no context and no framework.
struct BudgetAlertEvaluatorTests {
  private let groceries = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
  private let rent = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
  private let evaluator = BudgetAlertEvaluator()

  private func progress(
    _ categoryID: UUID,
    name: String = "Groceries",
    budgetMinor: Int = 1_000_000,
    spentMinor: Int,
    periodKey: String = "2026-08"
  ) -> BudgetProgress {
    BudgetProgress(
      id: categoryID,
      categoryName: name,
      paletteSlot: 0,
      budgetMinor: budgetMinor,
      spentMinor: spentMinor,
      fraction: Double(spentMinor) / Double(budgetMinor),
      periodKey: periodKey
    )
  }

  private var enabled: NotificationSettings {
    NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
  }

  private func key(_ categoryID: UUID, _ periodKey: String) -> String {
    BudgetAlertEvaluator.logKey(categoryID: categoryID, periodKey: periodKey)
  }

  // MARK: - AC: crossing with no log row

  @Test func crossingThresholdWithNoLogRowYieldsExactlyOneAlert() {
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 920_000)],
      firedKeys: [],
      settings: enabled
    )

    #expect(alerts.count == 1)
    #expect(alerts[0].categoryID == groceries)
    #expect(alerts[0].periodKey == "2026-08")
    #expect(alerts[0].wasSuppressed == false)
  }

  @Test func exactlyAtThresholdCrosses() {
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 900_000)],
      firedKeys: [],
      settings: enabled
    )

    #expect(alerts.count == 1)
    #expect(alerts[0].fraction == 0.9)
  }

  @Test func justUnderThresholdDoesNotCross() {
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 899_999)],
      firedKeys: [],
      settings: enabled
    )

    #expect(alerts.isEmpty)
  }

  @Test func thresholdComesFromSettingsNotAConstant() {
    let settings = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.5)
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 500_000)],
      firedKeys: [],
      settings: settings
    )

    #expect(alerts.count == 1)
  }

  // MARK: - AC: once per category per month

  @Test func crossingAgainInTheSameMonthYieldsZero() {
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 990_000)],
      firedKeys: [key(groceries, "2026-08")],
      settings: enabled
    )

    #expect(alerts.isEmpty)
  }

  @Test func aSuppressedRowSilencesTheRestOfThatMonthToo() {
    // The row U8 writes on toggle-on carries wasSuppressed = true. It is still a
    // row, so the key is still taken and nothing fires later that month.
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 1_400_000)],
      firedKeys: [key(groceries, "2026-08")],
      settings: enabled
    )

    #expect(alerts.isEmpty)
  }

  // MARK: - AC: the following month

  @Test func theFollowingMonthYieldsOne() {
    let alerts = evaluator.evaluate(
      [progress(groceries, spentMinor: 920_000, periodKey: "2026-09")],
      firedKeys: [key(groceries, "2026-08")],
      settings: enabled
    )

    #expect(alerts.count == 1)
    #expect(alerts[0].periodKey == "2026-09")
  }

  @Test func logKeyDistinguishesMonthsAndCategories() {
    #expect(key(groceries, "2026-08") != key(groceries, "2026-09"))
    #expect(key(groceries, "2026-08") != key(rent, "2026-08"))
  }

  // MARK: - AC: budget raised back above the threshold, then re-crossed

  @Test func budgetRaisedThenReCrossedYieldsZero() {
    let fired: Set<String> = [key(groceries, "2026-08")]

    // Budget raised from 10,000 to 20,000: 9,200 spent is now 46%.
    let afterRaise = evaluator.evaluate(
      [progress(groceries, budgetMinor: 2_000_000, spentMinor: 920_000)],
      firedKeys: fired,
      settings: enabled
    )
    #expect(afterRaise.isEmpty)

    // Spending climbs back over 90% of the new budget. The log row from the
    // first crossing is still there, so it stays quiet.
    let afterReCrossing = evaluator.evaluate(
      [progress(groceries, budgetMinor: 2_000_000, spentMinor: 1_900_000)],
      firedKeys: fired,
      settings: enabled
    )
    #expect(afterReCrossing.isEmpty)
  }

  // MARK: - AC: enabling alerts mid-month

  @Test func enablingMidMonthFiresNothingAndSuppressesEveryCrossedCategory() {
    let alerts = evaluator.evaluate(
      [
        progress(groceries, name: "Groceries", spentMinor: 920_000),
        progress(rent, name: "Rent", spentMinor: 1_500_000),
        progress(UUID(), name: "Health", spentMinor: 100_000),
      ],
      firedKeys: [],
      settings: enabled,
      trigger: .alertsEnabled
    )

    // One log row per already-crossed category — Health is at 10%, so two.
    #expect(alerts.count == 2)
    #expect(alerts.allSatisfy { $0.wasSuppressed })
    // Nothing to show.
    #expect(alerts.filter { !$0.wasSuppressed }.isEmpty)
  }

  @Test func enablingMidMonthDoesNotReLogACategoryThatAlreadyHasARow() {
    let alerts = evaluator.evaluate(
      [
        progress(groceries, name: "Groceries", spentMinor: 920_000),
        progress(rent, name: "Rent", spentMinor: 1_500_000),
      ],
      firedKeys: [key(groceries, "2026-08")],
      settings: enabled,
      trigger: .alertsEnabled
    )

    #expect(alerts.count == 1)
    #expect(alerts[0].categoryID == rent)
  }

  // MARK: - AC: disabled settings

  @Test func disabledSettingsYieldZeroRegardlessOfProgress() {
    let disabled = NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.9)
    let wayOver = [
      progress(groceries, spentMinor: 5_000_000),
      progress(rent, name: "Rent", spentMinor: 9_999_999),
    ]

    #expect(evaluator.evaluate(wayOver, firedKeys: [], settings: disabled).isEmpty)
    #expect(
      evaluator.evaluate(wayOver, firedKeys: [], settings: disabled, trigger: .alertsEnabled)
        .isEmpty
    )
  }

  // MARK: - Guards

  @Test func aRemovedBudgetNeverFires() {
    // setBudget(amountMinor: 0) means remove. A zero denominator arrives here as
    // .infinity, which satisfies any threshold.
    let removed = BudgetProgress(
      id: groceries,
      categoryName: "Groceries",
      paletteSlot: 0,
      budgetMinor: 0,
      spentMinor: 920_000,
      fraction: .infinity,
      periodKey: "2026-08"
    )

    #expect(evaluator.evaluate([removed], firedKeys: [], settings: enabled).isEmpty)
  }

  @Test func aNaNFractionNeverFires() {
    let nan = BudgetProgress(
      id: groceries,
      categoryName: "Groceries",
      paletteSlot: 0,
      budgetMinor: 1_000_000,
      spentMinor: 0,
      fraction: .nan,
      periodKey: "2026-08"
    )

    #expect(evaluator.evaluate([nan], firedKeys: [], settings: enabled).isEmpty)
  }

  @Test func emptyProgressYieldsZero() {
    #expect(evaluator.evaluate([], firedKeys: [], settings: enabled).isEmpty)
  }

  // MARK: - Ordering

  @Test func alertsAreOrderedByDescendingFractionThenName() {
    let alerts = evaluator.evaluate(
      [
        progress(groceries, name: "Groceries", spentMinor: 910_000),
        progress(rent, name: "Rent", spentMinor: 1_500_000),
        progress(UUID(), name: "Aardvark", spentMinor: 910_000),
      ],
      firedKeys: [],
      settings: enabled
    )

    #expect(alerts.map(\.categoryName) == ["Rent", "Aardvark", "Groceries"])
  }
}
