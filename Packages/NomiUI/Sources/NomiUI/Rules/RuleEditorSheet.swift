import NomiCore
import NomiPreview
import SwiftUI

/// Create-or-edit sheet for a rule (OR1; approved `RuleEditor` artboard). A
/// large sheet: Cancel left, "Save" right (text, not a pill, per SIMP §4 form
/// sheets). Three card groups under section labels: the pattern with its live
/// match count directly beneath it, the category, and "Only when". A non-system
/// rule ends with a "Delete rule" row that asks first.
///
/// The live match count comes from `RuleStore.preview(pattern:scope:)` as the
/// pattern is typed, per the U6 notes. Create/edit duality follows
/// `BudgetEditorSheet`: a new rule has no delete row, and a system rule can be
/// edited but not deleted (`RuleRowActions`).
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
  @State private var isConfirmingDelete = false

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

  /// The rule's own delete offer, from the same gate the row's swipe uses.
  private var offersDelete: Bool {
    guard let rule else { return false }
    return RuleRowActions.offered(isSystem: rule.isSystem).contains(.delete)
  }

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
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          sectionLabel("Pattern")
          patternCard
          sectionLabel("Category")
          categoryCard
          sectionLabel("Only when")
          scopeCard
          if !currentScope.isValidRange {
            Text("Min must be at or below max.")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          if let errorMessage {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          if offersDelete {
            NomiDestructiveRow(title: "Delete rule") {
              isConfirmingDelete = true
            }
            .padding(.horizontal, NomiSpacing.sm)
            .nomiCard(padding: EdgeInsets())
            .padding(.top, NomiSpacing.md)
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.xs)
      }
      .background(NomiColor.ground)
      .navigationTitle(isCreating ? "New Rule" : "Edit Rule")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel")
              .nomiTextStyle(.navAction)
              .foregroundStyle(NomiColor.navy)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            Text("Save")
              .nomiTextStyle(.navActionStrong)
              .foregroundStyle(NomiColor.navy)
          }
          .disabled(!canSave)
          .opacity(canSave ? 1 : 0.4)
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
      .alert("Delete rule?", isPresented: $isConfirmingDelete) {
        Button("Delete", role: .destructive) { performDelete() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Transactions this rule categorized keep their category. New transactions stop matching it. This can't be undone.")
      }
    }
    .nomiSheet(detents: [.large])
  }

  // MARK: - Fields

  private func sectionLabel(_ title: String) -> some View {
    Text(title)
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.dayHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
      .accessibilityAddTraits(.isHeader)
  }

  private var patternCard: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      TextField("*MERCHANT*", text: $pattern)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.characters)
        #endif
        .accessibilityLabel("Pattern")
      Text(matchCountLoadFailed ? "Couldn't load match count" : RuleMatchSummary.text(for: matchCount))
        .nomiTextStyle(.subhead)
        .foregroundStyle(matchCountLoadFailed ? NomiColor.inkSecondary : NomiColor.ink)
      Text("Digits never match — they are stripped before rules run.")
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, NomiSpacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
  }

  private var categoryCard: some View {
    fieldRow {
      Text("Category")
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: NomiSpacing.xs)
      Picker("Category", selection: $categoryID) {
        ForEach(categories) { category in
          Text(category.name).tag(Optional(category.id))
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .tint(NomiColor.navy)
    }
  }

  /// "Only when": Direction, Account, and one Amount row with Min and Max side
  /// by side. The four fields feed `currentScope`, and so the match count.
  private var scopeCard: some View {
    VStack(spacing: 0) {
      fieldRow {
        Text("Direction")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xs)
        Picker("Direction", selection: $direction) {
          Text("Either").tag(Direction?.none)
          Text("Debit").tag(Direction?.some(.debit))
          Text("Credit").tag(Direction?.some(.credit))
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(NomiColor.navy)
      }
      separator
      fieldRow {
        Text("Account")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xs)
        Picker("Account", selection: $scopeAccountID) {
          Text("Any").tag(UUID?.none)
          ForEach(accounts) { account in
            Text(account.displayName).tag(Optional(account.id))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(NomiColor.navy)
      }
      separator
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        HStack(spacing: NomiSpacing.xs) {
          Text("Amount")
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Spacer(minLength: NomiSpacing.xs)
          amountField(label: "Min", placeholder: "No minimum", text: $minAmountText, accessibility: "Minimum amount")
          amountField(label: "Max", placeholder: "No maximum", text: $maxAmountText, accessibility: "Maximum amount")
        }
      }
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xs)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
    .nomiCard(padding: EdgeInsets())
  }

  /// One 56 pt card row: the same chrome for the category picker and the scope
  /// pickers.
  private func fieldRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      content()
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
  }

  private var separator: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .padding(.horizontal, NomiSpacing.sm)
  }

  /// A 118 × 46 bordered box holding a short "Min"/"Max" label and a right-aligned
  /// amount. Sanitising is `EntryAmount`'s, the same rule the entry and budget
  /// fields use, so the three cannot disagree on what a valid amount is.
  private func amountField(label: String, placeholder: String, text: Binding<String>, accessibility: String) -> some View {
    HStack(spacing: NomiSpacing.xxs) {
      Text(label)
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
      TextField(placeholder, text: text)
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
        .multilineTextAlignment(.trailing)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
        .accessibilityLabel(accessibility)
        .onChange(of: text.wrappedValue) { _, newValue in
          let sanitized = EntryAmount.sanitizeInput(newValue)
          if sanitized != newValue { text.wrappedValue = sanitized }
        }
    }
    .padding(.horizontal, NomiSpacing.xs)
    .frame(width: 118, height: 46)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(NomiColor.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(NomiColor.separator, lineWidth: 1)
    )
  }

  // MARK: - Actions

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

  private func performDelete() {
    guard let rule else { return }
    do {
      try ruleStore.delete(rule.id)
      dismiss()
    } catch {
      errorMessage = "Could not delete rule."
    }
  }
}

#Preview("Rule editor — create, light") {
  RuleEditorSheet(ruleStore: FakeRuleStore(), categories: EntryRulesPreviewSupport.makeCategories(), accounts: [], rule: nil)
    .preferredColorScheme(.light)
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

#Preview("Rule editor — with a scope, light") {
  let fixture = makeScopedRuleFixture()
  RuleEditorSheet(ruleStore: FakeRuleStore(), categories: [fixture.category], accounts: [fixture.account], rule: fixture.rule)
    .preferredColorScheme(.light)
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

#Preview("Rule editor — match count fails to load, light") {
  RuleEditorSheet(ruleStore: AlwaysFailingPreviewRuleStore(), categories: EntryRulesPreviewSupport.makeCategories(), accounts: [], rule: nil)
    .preferredColorScheme(.light)
}
