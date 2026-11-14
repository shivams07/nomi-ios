import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Rules screen (U6; OR1). Shape from the approved `Rules` and `RulesEmpty`
/// artboards: an H0 "Rules" title with "+" in the nav bar, an "Order sets
/// priority" header that holds the Reorder/Done toggle, then one row per rule
/// (pattern, "<Category> · System", scope summary, enable switch). Pushed into
/// from Settings by U7 — public so that unit can construct it without reaching
/// into `NomiUI`'s internals.
public struct RulesScreen: View {
  public let ruleStore: RuleStore
  public let categoryStore: CategoryStore

  /// The account list for the editor's "Only when" section and this
  /// screen's own scope-summary line (W2-M4). A plain array, not `@Query`:
  /// `RulesScreen` is built against preview containers
  /// (`EntryRulesPreviewSupport.makeRulesContainer()` and this file's own
  /// `makeSystemRuleDisabledContainer()`), whose schema lists only
  /// `NomiCore.Category` and `NomiCore.Rule`, not `NomiCore.Account`.
  /// Defaulted to `[]` for previews. Production passes the live list from
  /// RootView through SettingsScreen (P-3, #111).
  public let accounts: [NomiCore.Account]

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

  public init(ruleStore: RuleStore, categoryStore: CategoryStore, accounts: [NomiCore.Account] = []) {
    self.ruleStore = ruleStore
    self.categoryStore = categoryStore
    self.accounts = accounts
  }

  private var isReordering: Bool {
    #if os(iOS)
    editMode.isEditing
    #else
    false
    #endif
  }

  public var body: some View {
    Group {
      if rules.isEmpty {
        emptyState
      } else {
        rulesList
      }
    }
    .background(NomiColor.ground)
    .navigationTitle("Rules")
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

  /// One 72-high row. The label is a `Button` that opens the editor; the
  /// switch sits to its right in its own hit area, so the two never share a
  /// tap. Swipe-to-delete is an accelerator and is offered only where
  /// `RuleRowActions` says so. It is a swipe action, not `onDelete`, because
  /// `onDelete` draws its delete minus in reorder mode too.
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
    .padding(.vertical, NomiSpacing.xs)
    .frame(minHeight: 72)
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

#Preview("Rules — default, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Rules — empty, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(rules: []), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.light)
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

#Preview("Rules — system rule, toggle off, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(makeSystemRuleDisabledContainer())
  .preferredColorScheme(.light)
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

#Preview("Rules — row with a scope summary, light") {
  let fixture = makeScopedRuleContainer()
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: fixture.accounts)
  }
  .modelContainer(fixture.container)
  .preferredColorScheme(.light)
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

#Preview("Rules — delete or reorder fails, light") {
  NavigationStack {
    RulesScreen(ruleStore: AlwaysFailingRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}
