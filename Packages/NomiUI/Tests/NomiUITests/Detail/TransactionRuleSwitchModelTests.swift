import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// The "Always use this" switch's model, the one the detail sheet drives (S3b).
/// The store is a spy that records its writes and can refuse them, so the
/// failed-write path is exercised through the same calls the view makes.
@MainActor
final class TransactionRuleSwitchModelTests: XCTestCase {

  private enum SpyError: Error { case refused, unused }

  /// A rule store that keeps its own rule list, so a re-read after a write sees
  /// what the write did, as the SwiftData store does.
  private final class SpyRuleStore: RuleStore {
    var rules: [TransactionDetailLogic.RuleRef] = []
    var createError: Error?
    var deleteError: Error?
    var readError: Error?
    /// Reads succeed until a write has been made, then fail: the re-read after a write.
    var readFailsAfterWrite = false
    var previewError: Error?
    private(set) var createCalls: [(pattern: String, categoryID: UUID)] = []
    private(set) var deleteCalls: [UUID] = []

    var hasWritten: Bool { !createCalls.isEmpty || !deleteCalls.isEmpty }

    func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
      createCalls.append((pattern, categoryID))
      if let createError { throw createError }
      rules.append(.init(id: UUID(), pattern: pattern, categoryID: categoryID, isSystem: false))
      return RuleApplyResult(matched: 4, recategorized: 3)
    }

    func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
      throw SpyError.unused
    }

    func setScope(_ id: UUID, _ scope: RuleScope) throws { throw SpyError.unused }
    func setEnabled(_ id: UUID, _ enabled: Bool) throws { throw SpyError.unused }

    func delete(_ id: UUID) throws {
      deleteCalls.append(id)
      if let deleteError { throw deleteError }
      rules.removeAll { $0.id == id }
    }

    func reorder(_ orderedIDs: [UUID]) throws { throw SpyError.unused }

    func preview(pattern: String, scope: RuleScope) throws -> Int {
      if let previewError { throw previewError }
      return 7
    }
  }

  private let food = UUID()
  private let pattern = "*OLACABS*"

  private func readRules(_ store: SpyRuleStore) throws -> [TransactionDetailLogic.RuleRef] {
    if let error = store.readError { throw error }
    if store.readFailsAfterWrite && store.hasWritten { throw SpyError.refused }
    return store.rules
  }

  private func refresh(_ model: TransactionRuleSwitchModel, store: SpyRuleStore, categoryID: UUID?) {
    model.refresh(pattern: pattern, categoryID: categoryID) { try self.readRules(store) }
  }

  private func toggle(_ model: TransactionRuleSwitchModel, store: SpyRuleStore, on: Bool, categoryID: UUID?) {
    model.setOn(on, pattern: pattern, categoryID: categoryID, ruleStore: store) { try self.readRules(store) }
  }

  // MARK: - Reading the switch

  func testSwitchReadsOffWhenNoRuleFilesThisMerchant() {
    let store = SpyRuleStore()
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    XCTAssertFalse(model.isOn)
    XCTAssertFalse(model.isSeeded)
  }

  func testSwitchReadsOnForAUserRuleWithThisPatternAndCategory() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: false)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    XCTAssertTrue(model.isOn)
    XCTAssertFalse(model.isSeeded)
  }

  /// A seeded rule for this pattern and category reads on and is locked, so the
  /// switch can neither create a duplicate nor delete the seeded rule.
  func testSwitchReadsOnAndIsSeededWhenTheSeededRuleFilesThisCategory() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: true)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    XCTAssertTrue(model.isOn)
    XCTAssertTrue(model.isSeeded)
  }

  func testRefreshWithoutAPatternReadsOffAndAsksNoStore() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: false)]
    let model = TransactionRuleSwitchModel()
    model.refresh(pattern: nil, categoryID: food) { try self.readRules(store) }
    XCTAssertFalse(model.isOn)
  }

  /// A read that fails leaves the switch off and says so, since it cannot show a
  /// rule it cannot read.
  func testUnreadableRulesReadOffWithAMessage() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: false)]
    store.readError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    XCTAssertFalse(model.isOn)
    XCTAssertEqual(model.errorMessage, "Could not read this rule.")
  }

  // MARK: - Seeded rules (S3b follow-up 2)

  /// Turning on for a merchant the seed already files under the same category
  /// creates nothing, so no duplicate user rule appears.
  func testTurningOnWithTheSeededCategoryCreatesNoDuplicate() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: true)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertEqual(store.createCalls.count, 0)
    XCTAssertEqual(store.rules.count, 1)
    XCTAssertNil(model.errorMessage)
  }

  /// A different category is an intentional override: the user rule is created and
  /// the switch reads on.
  func testTurningOnWithADifferentCategoryCreatesTheOverride() {
    let store = SpyRuleStore()
    let bills = UUID()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: true)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: bills)
    XCTAssertFalse(model.isOn)
    toggle(model, store: store, on: true, categoryID: bills)
    XCTAssertEqual(store.createCalls.map(\.categoryID), [bills])
    XCTAssertTrue(model.isOn)
    XCTAssertFalse(model.isSeeded)
    XCTAssertEqual(model.caption(), "Applied to 3 transactions")
  }

  /// The seeded rule cannot be removed, so the switch writes nothing on off.
  func testTurningOffASeededRuleDeletesNothing() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: true)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: false, categoryID: food)
    XCTAssertEqual(store.deleteCalls.count, 0)
    XCTAssertTrue(model.isOn)
  }

  // MARK: - Writes

  func testTurningOnCreatesTheRuleAndReadsOn() {
    let store = SpyRuleStore()
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertEqual(store.createCalls.count, 1)
    XCTAssertTrue(model.isOn)
    XCTAssertEqual(model.appliedCount, 3)
  }

  func testTurningOffDeletesTheUserRuleAndClearsTheAppliedNote() {
    let store = SpyRuleStore()
    let rule = UUID()
    store.rules = [.init(id: rule, pattern: pattern, categoryID: food, isSystem: false)]
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: false, categoryID: food)
    XCTAssertEqual(store.deleteCalls, [rule])
    XCTAssertFalse(model.isOn)
    XCTAssertNil(model.appliedCount)
  }

  // MARK: - Failed writes restore the prior switch state (S3a follow-up 3)

  /// A refused create shows the error, leaves the switch off as it was, and bumps
  /// the revision so the drawn switch snaps back.
  func testFailedCreateShowsAnErrorAndLeavesTheSwitchOff() {
    let store = SpyRuleStore()
    store.createError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    let revision = model.revision
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertEqual(store.createCalls.count, 1)
    XCTAssertFalse(model.isOn)
    XCTAssertEqual(model.errorMessage, "Could not save this rule.")
    XCTAssertEqual(model.revision, revision + 1)
    XCTAssertNil(model.appliedCount)
  }

  /// A refused delete shows the error and leaves the switch on as it was.
  func testFailedDeleteShowsAnErrorAndLeavesTheSwitchOn() {
    let store = SpyRuleStore()
    store.rules = [.init(id: UUID(), pattern: pattern, categoryID: food, isSystem: false)]
    store.deleteError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    let revision = model.revision
    toggle(model, store: store, on: false, categoryID: food)
    XCTAssertEqual(store.deleteCalls.count, 1)
    XCTAssertTrue(model.isOn)
    XCTAssertEqual(model.errorMessage, "Could not turn this rule off.")
    XCTAssertEqual(model.revision, revision + 1)
  }

  /// A create that lands but whose re-read then fails: the switch is not guessed
  /// at. It keeps the state it had, the error says the save failed, and the
  /// revision still moves so the drawn switch redraws.
  func testFailedRereadAfterAWriteKeepsThePriorStateAndShowsTheError() {
    let store = SpyRuleStore()
    store.readFailsAfterWrite = true
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    let revision = model.revision
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertEqual(store.createCalls.count, 1)
    XCTAssertFalse(model.isOn)
    XCTAssertEqual(model.errorMessage, "Could not save this rule.")
    XCTAssertEqual(model.revision, revision + 1)
  }

  // MARK: - Match count

  func testMatchCountIsReadWhenThePatternHasARuleStore() {
    let store = SpyRuleStore()
    let model = TransactionRuleSwitchModel()
    model.refreshMatchCount(pattern: pattern, ruleStore: store)
    XCTAssertEqual(model.caption(), "Matches 7 past transactions")
  }

  func testMatchCountIsLeftOutWhenItCannotBeRead() {
    let store = SpyRuleStore()
    store.previewError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    model.refreshMatchCount(pattern: pattern, ruleStore: store)
    XCTAssertNil(model.caption())
  }

  // MARK: - Error surfacing (fix round: the screen must show the switch's error)

  /// A refused write leaves its error on the model. A later write that lands clears it,
  /// so an old failure is not shown again after the switch works.
  func testSuccessfulToggleClearsAnEarlierError() {
    let store = SpyRuleStore()
    store.createError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertEqual(model.errorMessage, "Could not save this rule.")

    store.createError = nil
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertNil(model.errorMessage)
    XCTAssertTrue(model.isOn)
  }

  /// Dismissing the alert clears the switch's error, as the screen's own errors clear.
  func testClearErrorRemovesTheMessage() {
    let store = SpyRuleStore()
    store.createError = SpyError.refused
    let model = TransactionRuleSwitchModel()
    refresh(model, store: store, categoryID: food)
    toggle(model, store: store, on: true, categoryID: food)
    XCTAssertNotNil(model.errorMessage)

    model.clearError()
    XCTAssertNil(model.errorMessage)
  }
}
