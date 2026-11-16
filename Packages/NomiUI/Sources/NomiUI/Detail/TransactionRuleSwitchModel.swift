import Foundation
import NomiCore
import Observation

/// The "Always use this" switch on the transaction detail sheet, outside the view
/// (S3b), so plain XCTest can drive it against a store that refuses a write. The
/// sheet owns one through `@State`. The rules are read through a closure the view
/// supplies, fresh at each call, since the detail's `@Query` does not see a rule the
/// rule store has just written (see `TransactionDetailScreen.storedRules`).
@Observable @MainActor final class TransactionRuleSwitchModel {
  /// What the switch draws. Only a read of the store sets it, or a write the store
  /// accepted; a refused write leaves it where it was.
  private(set) var isOn = false
  /// True when a seeded rule files this row's merchant under its category and no
  /// user rule does. The switch then reads on and is locked (see `TransactionDetailLogic.ruleSwitchEnabled`).
  private(set) var isSeeded = false
  /// Bumped when a write fails, so the drawn switch redraws in its prior state.
  private(set) var revision = 0
  /// How many past rows the pattern matches. Nil when it cannot be read.
  private(set) var matchCount: Int?
  /// Set after a switch-on, for the two-second note that says what it recategorised.
  private(set) var appliedCount: Int?
  var errorMessage: String?

  init() {}

  /// Reads the switch for this row. A read that fails leaves the switch off and says
  /// so, since the switch cannot show a rule it cannot read.
  func refresh(pattern: String?, categoryID: UUID?, rules: () throws -> [TransactionDetailLogic.RuleRef]) {
    guard let pattern else {
      apply(SwitchState(isOn: false, isSeeded: false))
      return
    }
    do {
      apply(state(in: try rules(), pattern: pattern, categoryID: categoryID))
    } catch {
      apply(SwitchState(isOn: false, isSeeded: false))
      errorMessage = "Could not read this rule."
    }
  }

  /// Carries out one toggle. The decision comes from a fresh read of the store
  /// (`TransactionDetailLogic.ruleSwitchAction`). The switch is then set from the
  /// store again. A refused write shows an error, sets the switch from the store as
  /// it stands, and bumps `revision`, so the switch is drawn in its prior state.
  func setOn(
    _ turningOn: Bool, pattern: String, categoryID: UUID?, ruleStore: RuleStore?,
    rules: () throws -> [TransactionDetailLogic.RuleRef]
  ) {
    do {
      let before = try rules()
      let decision = decide(turningOn: turningOn, in: before, pattern: pattern, categoryID: categoryID)
      switch decision {
      case .none:
        break
      case .create(let createCategoryID):
        // The store re-applies the rule across the ledger; the result says how many
        // past rows it recategorised.
        guard let ruleStore else { break }
        let result = try ruleStore.create(pattern: pattern, categoryID: createCategoryID)
        appliedCount = result.recategorized
      case .delete(let id):
        // Rows keep their categories: that is the store's existing policy for a
        // deleted rule.
        guard let ruleStore else { break }
        try ruleStore.delete(id)
        appliedCount = nil
      }
      apply(state(in: try rules(), pattern: pattern, categoryID: categoryID))
      refreshMatchCount(pattern: pattern, ruleStore: ruleStore)
    } catch {
      errorMessage = turningOn ? "Could not save this rule." : "Could not turn this rule off."
      appliedCount = nil
      if let after = try? rules() {
        apply(state(in: after, pattern: pattern, categoryID: categoryID))
      }
      revision += 1
    }
  }

  /// The past-row count for this row's pattern. A count that cannot be read is left
  /// out, the same as the suggestion: it is an aid, not an action.
  func refreshMatchCount(pattern: String?, ruleStore: RuleStore?) {
    guard let ruleStore, let pattern else {
      matchCount = nil
      return
    }
    do {
      matchCount = try ruleStore.preview(pattern: pattern)
    } catch {
      matchCount = nil
    }
  }

  /// Called when the two-second "Applied to" note has run its course.
  func clearAppliedNote() {
    appliedCount = nil
  }

  /// The line under the switch: the note after a switch-on, else the match count.
  func caption() -> String? {
    if let appliedCount {
      return TransactionDetailLogic.appliedText(count: appliedCount)
    }
    guard let matchCount else { return nil }
    return TransactionDetailLogic.matchCountText(count: matchCount, isOn: isOn)
  }

  // MARK: - Helpers

  private struct SwitchState: Equatable {
    let isOn: Bool
    let isSeeded: Bool
  }

  /// The user rule the switch reads, and whether a seeded rule covers the row with
  /// no user rule on top of it. A user rule wins: it can be turned off, the seeded
  /// one cannot.
  private func state(
    in rules: [TransactionDetailLogic.RuleRef], pattern: String, categoryID: UUID?
  ) -> SwitchState {
    guard let categoryID else { return SwitchState(isOn: false, isSeeded: false) }
    let userRule = TransactionDetailLogic.existingRuleID(among: rules, pattern: pattern, categoryID: categoryID) != nil
    let seeded = TransactionDetailLogic.systemRuleCovers(among: rules, pattern: pattern, categoryID: categoryID)
    return SwitchState(isOn: userRule || seeded, isSeeded: seeded && !userRule)
  }

  private func decide(
    turningOn: Bool, in rules: [TransactionDetailLogic.RuleRef], pattern: String, categoryID: UUID?
  ) -> TransactionDetailLogic.RuleSwitchAction {
    let userRuleID = categoryID.flatMap {
      TransactionDetailLogic.existingRuleID(among: rules, pattern: pattern, categoryID: $0)
    }
    let seeded = categoryID.map {
      TransactionDetailLogic.systemRuleCovers(among: rules, pattern: pattern, categoryID: $0)
    } ?? false
    return TransactionDetailLogic.ruleSwitchAction(
      turningOn: turningOn, existingRuleID: userRuleID, categoryID: categoryID, seededCovers: seeded)
  }

  private func apply(_ state: SwitchState) {
    isOn = state.isOn
    isSeeded = state.isSeeded
  }
}
