import NomiCore
import NomiPreview
import SwiftUI

/// Create-or-edit sheet for a rule. Shows the live match count from
/// `RuleStore.preview(pattern:)` as the pattern is typed, per the U6 notes.
/// This is a form screen reached through Categories/Rules navigation, not the
/// two-tap entry path — a `Picker` here does not violate that done-when.
struct RuleEditorSheet: View {
  let ruleStore: RuleStore
  let categories: [NomiCore.Category]
  let accounts: [NomiCore.Account]
  let rule: NomiCore.Rule?

  @Environment(\.dismiss) private var dismiss
  @State private var pattern: String
  @State private var categoryID: UUID?
  @State private var direction: Direction?
  @State private var scopeAccountID: UUID?
  @State private var minAmountText: String
  @State private var maxAmountText: String
  @State private var matchCount = 0
  @State private var matchCountLoadFailed = false
  @State private var errorMessage: String?

  init(ruleStore: RuleStore, categories: [NomiCore.Category], accounts: [NomiCore.Account], rule: NomiCore.Rule?) {
    self.ruleStore = ruleStore
    self.categories = categories
    self.accounts = accounts
    self.rule = rule
    _pattern = State(initialValue: rule?.pattern ?? "")
    _categoryID = State(initialValue: rule?.categoryID ?? categories.first?.id)
    let scope = rule?.scope ?? .any
    _direction = State(initialValue: scope.direction)
    _scopeAccountID = State(initialValue: scope.accountID)
    _minAmountText = State(initialValue: scope.minAmountMinor.map { String(format: "%.2f", Double($0) / 100) } ?? "")
    _maxAmountText = State(initialValue: scope.maxAmountMinor.map { String(format: "%.2f", Double($0) / 100) } ?? "")
  }

  private var isCreating: Bool { rule == nil }

  /// The scope the "Only when" section currently describes — rebuilt from
  /// the four fields on every access rather than held as its own `@State`,
  /// so the fields stay the single source of truth and can never drift from
  /// what this computes.
  private var currentScope: RuleScope {
    RuleScope(
      direction: direction,
      accountID: scopeAccountID,
      minAmountMinor: RuleScopeAmount.bound(from: minAmountText),
      maxAmountMinor: RuleScopeAmount.bound(from: maxAmountText)
    )
  }

  private var canSave: Bool { RuleFormGate.isValid(pattern: pattern, categoryID: categoryID, scope: currentScope) }

  /// `.task(id:)`'s identity for the debounced match-count fetch — pattern
  /// alone used to be enough, but the scope narrows the count too (W2-M4:
  /// "narrowing a scope can only ever lower the number"), so a scope edit
  /// with no pattern edit has to refire it just the same.
  private struct MatchCountQuery: Equatable {
    let pattern: String
    let scope: RuleScope
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Pattern") {
          TextField("*MERCHANT*", text: $pattern)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
          Text("Digits never match — they are stripped before rules run.")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
        Section("Category") {
          Picker("Category", selection: $categoryID) {
            ForEach(categories) { category in
              Text(category.name).tag(Optional(category.id))
            }
          }
        }
        Section("Only when") {
          Picker("Direction", selection: $direction) {
            Text("Either").tag(Direction?.none)
            Text("Debit").tag(Direction?.some(.debit))
            Text("Credit").tag(Direction?.some(.credit))
          }
          Picker("Account", selection: $scopeAccountID) {
            Text("Any").tag(UUID?.none)
            ForEach(accounts) { account in
              Text(account.displayName).tag(Optional(account.id))
            }
          }
          HStack {
            Text("Min")
              .foregroundStyle(NomiColor.textTertiary)
            TextField("No minimum", text: $minAmountText)
              #if os(iOS)
              .keyboardType(.decimalPad)
              #endif
              .multilineTextAlignment(.trailing)
              .onChange(of: minAmountText) { _, newValue in
                let sanitized = EntryAmount.sanitizeInput(newValue)
                if sanitized != newValue { minAmountText = sanitized }
              }
          }
          HStack {
            Text("Max")
              .foregroundStyle(NomiColor.textTertiary)
            TextField("No maximum", text: $maxAmountText)
              #if os(iOS)
              .keyboardType(.decimalPad)
              #endif
              .multilineTextAlignment(.trailing)
              .onChange(of: maxAmountText) { _, newValue in
                let sanitized = EntryAmount.sanitizeInput(newValue)
                if sanitized != newValue { maxAmountText = sanitized }
              }
          }
          if !currentScope.isValidRange {
            Text("Min must be at or below max.")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.overBudget)
          }
        }
        Section {
          if matchCountLoadFailed {
            Text("Couldn't load match count")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          } else {
            Text(RuleMatchSummary.text(for: matchCount))
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
        }
        if let errorMessage {
          Section {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.overBudget)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle(isCreating ? "New Rule" : "Edit Rule")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
        }
      }
      .task(id: MatchCountQuery(pattern: pattern, scope: currentScope)) {
        // Debounced (L2): a fast typist would otherwise fire `preview(pattern:scope:)`
        // once per keystroke. `.task(id:)` cancels the previous sleep the
        // moment the query changes again, so only the settled value ever
        // reaches the store — including the very first, undebounced render,
        // which is what used to need a separate `.onAppear` call. The query
        // now carries scope too (W2-M4), so editing "Only when" refires this
        // exactly as editing the pattern always has.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        updateMatchCount(pattern: pattern, scope: currentScope)
      }
    }
  }

  private func updateMatchCount(pattern: String, scope: RuleScope) {
    do {
      matchCount = try ruleStore.preview(pattern: pattern, scope: scope)
      matchCountLoadFailed = false
    } catch {
      matchCountLoadFailed = true
    }
  }

  private func save() {
    guard canSave, let categoryID else { return }
    do {
      if let rule {
        try ruleStore.update(rule.id, pattern: pattern, categoryID: categoryID, scope: currentScope)
      } else {
        try ruleStore.create(pattern: pattern, categoryID: categoryID, scope: currentScope)
      }
      dismiss()
    } catch {
      errorMessage = "Could not save rule."
    }
  }
}

#Preview("Rule editor — create, dark") {
  RuleEditorSheet(ruleStore: FakeRuleStore(), categories: EntryRulesPreviewSupport.makeCategories(), accounts: [], rule: nil)
    .preferredColorScheme(.dark)
}

/// `NomiCore.Account`/`Rule` are `@Model`s — safe to construct here (a
/// `#Preview` body), not inside a test function (see `RuleScopeSummary`'s own
/// note on why it avoids needing one at all).
private func makeScopedRuleFixture() -> (rule: NomiCore.Rule, category: NomiCore.Category, account: NomiCore.Account) {
  let category = EntryRulesPreviewSupport.makeCategories()[0]
  let account = NomiCore.Account(displayName: "HDFC •• 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank")
  let rule = NomiCore.Rule(
    pattern: "*SWIGGY*",
    categoryID: category.id,
    scope: RuleScope(direction: .debit, accountID: account.id, minAmountMinor: 100_00, maxAmountMinor: 2000_00)
  )
  return (rule, category, account)
}

#Preview("Rule editor — with a scope, dark") {
  let fixture = makeScopedRuleFixture()
  RuleEditorSheet(ruleStore: FakeRuleStore(), categories: [fixture.category], accounts: [fixture.account], rule: fixture.rule)
    .preferredColorScheme(.dark)
}

private struct RuleEditorMatchCountFailure: Error {}

/// `preview(pattern:scope:)` always throws, so the `.task(id:)`'s first,
/// undebounced firing surfaces the "Couldn't load match count" state as soon
/// as the canvas renders.
@MainActor
private final class AlwaysFailingPreviewRuleStore: RuleStore {
  @discardableResult
  func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    RuleApplyResult(matched: 0, recategorized: 0)
  }

  @discardableResult
  func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    RuleApplyResult(matched: 0, recategorized: 0)
  }

  func setScope(_ id: UUID, _ scope: RuleScope) throws {}
  func setEnabled(_ id: UUID, _ enabled: Bool) throws {}
  func delete(_ id: UUID) throws {}
  func reorder(_ orderedIDs: [UUID]) throws {}
  func preview(pattern: String, scope: RuleScope) throws -> Int { throw RuleEditorMatchCountFailure() }
}

#Preview("Rule editor — match count fails to load, dark") {
  RuleEditorSheet(ruleStore: AlwaysFailingPreviewRuleStore(), categories: EntryRulesPreviewSupport.makeCategories(), accounts: [], rule: nil)
    .preferredColorScheme(.dark)
}
