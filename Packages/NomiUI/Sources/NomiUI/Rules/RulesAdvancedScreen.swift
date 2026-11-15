import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// "Order and patterns" (S10): every rule as its raw glob pattern, in priority
/// order, with drag-to-reorder and the swipe actions. This is the list the
/// Rules screen had before S10, moved here as it was; the sentence rows on
/// `RulesScreen` link to it through "Advanced: order and patterns".
struct RulesAdvancedScreen: View {
  let ruleStore: RuleStore
  let categoryStore: CategoryStore

  /// The account list for the editor's "Only when" section and this
  /// screen's own scope-summary line. Passed in from `RulesScreen`, which
  /// receives it from Settings.
  let accounts: [NomiCore.Account]

  @Query(sort: \NomiCore.Rule.priority) private var rules: [NomiCore.Rule]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingRule: NomiCore.Rule?
  /// The rule a swipe-delete has asked about. Nothing is deleted until the
  /// confirmation's Delete is tapped (Y7).
  @State private var pendingDelete: NomiCore.Rule?
  @State private var isCreating = false
  @State private var actionError = false
  #if os(iOS)
  /// Drives the list's reorder mode. Handles appear only while this is active
  /// (SIMP §3 item 18: the always-visible ≡ glyph and the nav-bar Edit are cut).
  @State private var editMode: EditMode = .inactive
  #endif

  private var isReordering: Bool {
    #if os(iOS)
    editMode.isEditing
    #else
    false
    #endif
  }

  var body: some View {
    Group {
      if rules.isEmpty {
        emptyState
      } else {
        rulesList
      }
    }
    .background(NomiColor.ground)
    .navigationTitle("Order and patterns")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreating = true
        } label: {
          NomiNavIcon(systemName: "plus")
        }
        .accessibilityLabel("Add rule")
      }
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

  // MARK: - States

  private var emptyState: some View {
    ScrollView {
      NomiEmptyState(
        systemImage: "line.3.horizontal.decrease",
        title: "No rules yet",
        message: "A rule sets a category when a transaction's description matches its pattern.",
        actionTitle: "Add rule"
      ) {
        isCreating = true
      }
      .padding(.top, 96)
      .padding(.horizontal, NomiSpacing.screenGutter)
    }
  }

  // MARK: - List

  private var rulesList: some View {
    List {
      Section {
        ForEach(rules) { rule in
          row(for: rule)
        }
        .onMove(perform: move)
      } header: {
        listHeader
      }
    }
    .scrollContentBackground(.hidden)
    #if os(iOS)
    .listStyle(.insetGrouped)
    .environment(\.editMode, $editMode)
    #endif
    // An alert, not a confirmationDialog: on iPhone a dialog anchored to the
    // swipe row renders as a popover with no Cancel. An alert is always a
    // centred modal with its own Cancel. It sits on the List, not beside the
    // error alert on the body, so the two presentations never share a node.
    .alert(
      RuleDeleteConfirmation.title,
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { rule in
      Button(RuleDeleteConfirmation.confirm, role: .destructive) {
        delete(rule)
      }
      Button(RuleDeleteConfirmation.cancel, role: .cancel) {}
    } message: { _ in
      Text(RuleDeleteConfirmation.message)
    }
  }

  /// 44 high: the caption on the left, the Reorder/Done text button (44 hit) on
  /// the right. The button is iOS-only because reorder mode is a `List`
  /// edit mode that AppKit does not have.
  private var listHeader: some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      Text("Order sets priority")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
      Spacer(minLength: NomiSpacing.xs)
      #if os(iOS)
      Button {
        editMode = editMode.isEditing ? .inactive : .active
      } label: {
        Text(editMode.isEditing ? "Done" : "Reorder")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.navy)
          .frame(minHeight: NomiSpacing.minTarget)
          .padding(.horizontal, NomiSpacing.xxs)
      }
      #endif
    }
    .frame(height: NomiSpacing.navRowHeight)
  }

  /// One row: the label is a `Button` that opens the editor; the switch sits
  /// to its right in its own hit area, so the two never share a tap.
  /// Swipe-to-delete is an accelerator and is offered only where
  /// `RuleRowActions` says so. It is a swipe action, not `onDelete`, because
  /// `onDelete` draws its delete minus in reorder mode too.
  ///
  /// D11: the List's default row insets made each row about 102 pt; the
  /// insets are zeroed vertically here and the row carries its own 10 pt.
  private func row(for rule: NomiCore.Rule) -> some View {
    let categoryName = categories.first(where: { $0.id == rule.categoryID })?.name ?? "Uncategorized"
    let scopeSummary = RuleScopeSummary.text(
      for: rule.scope,
      accountName: { id in accounts.first(where: { $0.id == id })?.displayName }
    )
    return HStack(spacing: NomiSpacing.sm) {
      Button {
        editingRule = rule
      } label: {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(rule.pattern)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Text(RuleRowSubtitle.text(categoryName: categoryName, isSystem: rule.isSystem))
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
          if let scopeSummary {
            Text(scopeSummary)
              .nomiTextStyle(.footnote)
              .foregroundStyle(NomiColor.inkSecondary)
          }
        }
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isReordering)
      Toggle(
        "Enable rule \(rule.pattern)",
        isOn: Binding(
          get: { rule.isEnabled },
          set: { setEnabled(rule, $0) }
        )
      )
      .labelsHidden()
      .tint(NomiColor.navy)
      .frame(minHeight: NomiSpacing.minTarget)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 72)
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    .listRowBackground(NomiColor.card)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if RuleRowActions.offered(isSystem: rule.isSystem).contains(.delete) {
        Button(role: .destructive) {
          pendingDelete = rule
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
  }

  // MARK: - Actions

  private func setEnabled(_ rule: NomiCore.Rule, _ enabled: Bool) {
    do {
      try ruleStore.setEnabled(rule.id, enabled)
    } catch {
      actionError = true
    }
  }

  private func delete(_ rule: NomiCore.Rule) {
    do {
      try ruleStore.delete(rule.id)
    } catch {
      actionError = true
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

#Preview("Order and patterns — default, light") {
  NavigationStack {
    RulesAdvancedScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: [])
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Order and patterns — empty, light") {
  NavigationStack {
    RulesAdvancedScreen(ruleStore: FakeRuleStore(rules: []), categoryStore: FakeCategoryStore(), accounts: [])
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.light)
}

/// A container built locally to this file rather than through
/// `EntryRulesPreviewSupport`, whose `makeRulesContainer()` seeds only user
/// rules, none disabled.
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

#Preview("Order and patterns — system rule, toggle off, light") {
  NavigationStack {
    RulesAdvancedScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: [])
  }
  .modelContainer(makeSystemRuleDisabledContainer())
  .preferredColorScheme(.light)
}

/// Local, `Account`-inclusive container for the preview below that needs a
/// scoped rule (W2-M4). `EntryRulesPreviewSupport.makeRulesContainer()`'s schema
/// is `[Category, Rule]` with no `Account`.
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

#Preview("Order and patterns — row with a scope summary, light") {
  let fixture = makeScopedRuleContainer()
  NavigationStack {
    RulesAdvancedScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: fixture.accounts)
  }
  .modelContainer(fixture.container)
  .preferredColorScheme(.light)
}

private struct RulesAdvancedActionFailure: Error {}

/// Delete, reorder, and setEnabled all always throw, so swiping to delete,
/// dragging a row, or flipping its toggle exercises the `actionError` alert.
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

  func setScope(_ id: UUID, _ scope: RuleScope) throws { throw RulesAdvancedActionFailure() }
  func setEnabled(_ id: UUID, _ enabled: Bool) throws { throw RulesAdvancedActionFailure() }
  func delete(_ id: UUID) throws { throw RulesAdvancedActionFailure() }
  func reorder(_ orderedIDs: [UUID]) throws { throw RulesAdvancedActionFailure() }
  func preview(pattern: String, scope: RuleScope) throws -> Int { 0 }
}

#Preview("Order and patterns — delete or reorder fails, light") {
  NavigationStack {
    RulesAdvancedScreen(ruleStore: AlwaysFailingRuleStore(), categoryStore: FakeCategoryStore(), accounts: [])
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}
