import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Rules screen (U6): drag-to-reorder priority, live match count on
/// create/edit. Pushed into from Settings by U7 — public so that unit can
/// construct it without reaching into `NomiUI`'s internals.
public struct RulesScreen: View {
  public let ruleStore: RuleStore
  public let categoryStore: CategoryStore

  /// The account list for the editor's "Only when" section and this
  /// screen's own scope-summary line (W2-M4). A plain array, not `@Query`:
  /// `RulesScreen` is built against preview/test containers
  /// (`EntryRulesPreviewSupport.makeRulesContainer()` and this file's own
  /// `makeSystemRuleDisabledContainer()`) whose schema doesn't include
  /// `NomiCore.Account` — an `@Query` here would crash every one of them,
  /// not just the ones that care about scope. Defaulted to `[]` so
  /// `RootView`'s existing call site keeps compiling unchanged; wiring the
  /// real account list through from there is follow-up, not this unit's file
  /// to touch.
  public let accounts: [NomiCore.Account]

  @Query(sort: \NomiCore.Rule.priority) private var rules: [NomiCore.Rule]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingRule: NomiCore.Rule?
  @State private var isCreating = false
  @State private var actionError = false

  public init(ruleStore: RuleStore, categoryStore: CategoryStore, accounts: [NomiCore.Account] = []) {
    self.ruleStore = ruleStore
    self.categoryStore = categoryStore
    self.accounts = accounts
  }

  public var body: some View {
    List {
      ForEach(rules) { rule in
        row(for: rule)
          .deleteDisabled(!RuleRowActions.offered(isSystem: rule.isSystem).contains(.delete))
      }
      .onDelete(perform: delete)
      .onMove(perform: move)
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Rules")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreating = true
        } label: {
          Image(systemName: "plus")
        }
      }
      #if os(iOS)
      ToolbarItem(placement: .navigationBarLeading) {
        EditButton()
      }
      #endif
    }
    .sheet(isPresented: $isCreating) {
      RuleEditorSheet(ruleStore: ruleStore, categories: categories, accounts: accounts, rule: nil)
    }
    .sheet(item: $editingRule) { rule in
      RuleEditorSheet(ruleStore: ruleStore, categories: categories, accounts: accounts, rule: rule)
    }
    .alert("Couldn't update rules", isPresented: $actionError) {
      Button("OK", role: .cancel) {}
    }
  }

  private func row(for rule: NomiCore.Rule) -> some View {
    let categoryName = categories.first(where: { $0.id == rule.categoryID })?.name ?? "Uncategorized"
    return HStack(spacing: NomiSpacing.xs) {
      HStack(spacing: NomiSpacing.xs) {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(NomiColor.textTertiary)
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(rule.pattern)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
          HStack(spacing: NomiSpacing.xxs) {
            Text(categoryName)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            if rule.isSystem {
              Text("System")
                .nomiTextStyle(.caption)
                .foregroundStyle(NomiColor.textTertiary)
            }
          }
          if let scopeSummary = RuleScopeSummary.text(
            for: rule.scope,
            accountName: { id in accounts.first(where: { $0.id == id })?.displayName }
          ) {
            Text(scopeSummary)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
        }
      }
      // Scoped to the label, not the whole row: a `Toggle` sits to its right,
      // and an `onTapGesture` spanning both would fight the toggle for the
      // tap that lands on it.
      .contentShape(Rectangle())
      .onTapGesture { editingRule = rule }
      Spacer()
      Toggle(
        "",
        isOn: Binding(
          get: { rule.isEnabled },
          set: { setEnabled(rule, $0) }
        )
      )
      .labelsHidden()
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  private func setEnabled(_ rule: NomiCore.Rule, _ enabled: Bool) {
    do {
      try ruleStore.setEnabled(rule.id, enabled)
    } catch {
      actionError = true
    }
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      do {
        try ruleStore.delete(rules[index].id)
      } catch {
        actionError = true
      }
    }
  }

  private func move(from source: IndexSet, to destination: Int) {
    let orderedIDs = RulesReorder.orderedIDs(current: rules.map(\.id), from: source, to: destination)
    do {
      try ruleStore.reorder(orderedIDs)
    } catch {
      actionError = true
    }
  }
}

#Preview("Rules — default, dark") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.dark)
}

#Preview("Rules — empty, dark") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(rules: []), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.dark)
}

/// A container built locally to this file rather than through
/// `EntryRulesPreviewSupport` — that file is untouched by this unit (no new
/// `@Query`, per the design note), and its `makeRulesContainer()` seeds only
/// user rules, none disabled.
@MainActor
private func makeSystemRuleDisabledContainer() -> ModelContainer {
  let container = try! ModelContainer(
    for: Schema([NomiCore.Category.self, NomiCore.Rule.self]),
    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
  )
  let category = NomiCore.Category(
    name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0
  )
  container.mainContext.insert(category)
  container.mainContext.insert(
    NomiCore.Rule(pattern: "*SWIGGY*", categoryID: category.id, priority: 0, isEnabled: false, isSystem: true)
  )
  return container
}

#Preview("Rules — system rule, toggle off, dark") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(makeSystemRuleDisabledContainer())
  .preferredColorScheme(.dark)
}

/// Local, `Account`-inclusive container for the one preview below that needs
/// a scoped rule (W2-M4) — `EntryRulesPreviewSupport.makeRulesContainer()`'s
/// schema is `[Category, Rule]` with no `Account`, and widening it is that
/// file's call, not this unit's (see `accounts`'s own note on `RulesScreen`).
@MainActor
private func makeScopedRuleContainer() -> (container: ModelContainer, accounts: [NomiCore.Account]) {
  let container = try! ModelContainer(
    for: Schema([NomiCore.Category.self, NomiCore.Rule.self, NomiCore.Account.self]),
    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
  )
  let category = NomiCore.Category(name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: true, sortIndex: 0)
  let account = NomiCore.Account(displayName: "HDFC •• 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank")
  container.mainContext.insert(category)
  container.mainContext.insert(account)
  container.mainContext.insert(
    NomiCore.Rule(
      pattern: "*AMAZON*",
      categoryID: category.id,
      priority: 0,
      scope: RuleScope(direction: .debit, accountID: account.id, minAmountMinor: 100_00, maxAmountMinor: 2000_00)
    )
  )
  return (container, [account])
}

#Preview("Rules — row with a scope summary, dark") {
  let fixture = makeScopedRuleContainer()
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: fixture.accounts)
  }
  .modelContainer(fixture.container)
  .preferredColorScheme(.dark)
}

private struct RulesScreenActionFailure: Error {}

/// Delete, reorder, and now `setEnabled` all always throw, so swiping to
/// delete, dragging a row, or flipping its toggle in the canvas exercises the
/// `actionError` alert.
///
/// `setScope` throws too, for consistency, but nothing on this screen or the
/// editor calls it: W2-M4's "Only when" section saves the whole rule through
/// `update`/`create`, the same as a pattern or category edit does.
/// `setScope` is for a scope-only write with no row for it yet (a swipe
/// action, maybe) — see its own doc comment on `RuleStore`.
@MainActor
private final class AlwaysFailingRuleStore: RuleStore {
  @discardableResult
  func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    RuleApplyResult(matched: 0, recategorized: 0)
  }

  @discardableResult
  func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    RuleApplyResult(matched: 0, recategorized: 0)
  }

  func setScope(_ id: UUID, _ scope: RuleScope) throws { throw RulesScreenActionFailure() }
  func setEnabled(_ id: UUID, _ enabled: Bool) throws { throw RulesScreenActionFailure() }
  func delete(_ id: UUID) throws { throw RulesScreenActionFailure() }
  func reorder(_ orderedIDs: [UUID]) throws { throw RulesScreenActionFailure() }
  func preview(pattern: String, scope: RuleScope) throws -> Int { 0 }
}

#Preview("Rules — delete or reorder fails, dark") {
  NavigationStack {
    RulesScreen(ruleStore: AlwaysFailingRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.dark)
}
