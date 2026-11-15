import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// Auto-categorise (S10; canvas `Rules`, artboard "Auto-categorise (was Rules)").
/// Each rule reads as a sentence: the merchant it names, the scope it applies
/// to, and the category it files under. Two sections: "Yours" (the user's
/// rules, editable and deletable) and "Built in" (the seeded rules, switch
/// only). The raw patterns, reorder and the swipe actions sit one row down in
/// "Order and patterns" (`RulesAdvancedScreen`). Pushed into from Settings, so
/// the public init is what SettingsScreen builds.
public struct RulesScreen: View {
  public let ruleStore: RuleStore
  public let categoryStore: CategoryStore

  /// The account list for each row's scope line and the editor's "Only when"
  /// section. A plain array, not `@Query`: `RulesScreen` is built against
  /// preview containers whose schema lists no `NomiCore.Account`. Defaulted to
  /// `[]` for previews. Production passes the live list from RootView through
  /// SettingsScreen (P-3, #111).
  public let accounts: [NomiCore.Account]

  @Query(sort: \NomiCore.Rule.priority) private var rules: [NomiCore.Rule]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingRule: NomiCore.Rule?
  /// The rule a swipe-delete has asked about. Nothing is deleted until the
  /// confirmation's Delete is tapped (Y7).
  @State private var pendingDelete: NomiCore.Rule?
  @State private var isCreating = false
  @State private var actionError = false
  /// The search field's text. Filters both sections by title and category.
  @State private var query = ""
  /// "Show all" on the built-in section. Resets when the screen goes away.
  @State private var showsAllBuiltIn = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(ruleStore: RuleStore, categoryStore: CategoryStore, accounts: [NomiCore.Account] = []) {
    self.ruleStore = ruleStore
    self.categoryStore = categoryStore
    self.accounts = accounts
  }

  private var userRules: [NomiCore.Rule] { rules.filter { !$0.isSystem } }
  private var builtInRules: [NomiCore.Rule] { rules.filter(\.isSystem) }

  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The rules a search keeps, in the order the section already holds them.
  private func matching(_ rules: [NomiCore.Rule]) -> [NomiCore.Rule] {
    rules.filter {
      RuleDisplay.matchesSearch(
        query,
        title: RuleDisplay.title(pattern: $0.pattern),
        categoryName: categoryName(for: $0)
      )
    }
  }

  public var body: some View {
    List {
      introSection
      if isSearching && matching(userRules).isEmpty && matching(builtInRules).isEmpty {
        noMatchSection
      } else {
        yoursSection
        builtInSection
        if !userRules.isEmpty && !isSearching {
          noteSection
        }
      }
      advancedSection
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.ground)
    #if os(iOS)
    .listStyle(.insetGrouped)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .navigationTitle("Auto-categorise")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreating = true
        } label: {
          Text("New rule", bundle: .module)
            .padding(.horizontal, NomiSpacing.sm)
        }
        .buttonStyle(NomiPrimaryButtonStyle(height: 44))
        .fixedSize()
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
    // An alert, not a confirmationDialog: on iPhone a dialog anchored to the
    // swipe row renders as a popover with no Cancel. An alert is always a
    // centred modal with its own Cancel (R9b, Y7).
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
    .onDisappear {
      showsAllBuiltIn = false
    }
  }

  // MARK: - Sections

  /// The explainer from the board, then the search field.
  private var introSection: some View {
    Section {
      Text(
        "When a payment's name contains the words on the left, Nomi files it under the category on the right. The first match from the top wins.",
        bundle: .module
      )
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.inkSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

      NomiSearchField(prompt: "Search merchants", text: $query)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
  }

  /// "Yours · N". Its body is the user's rules, or, with none, the one note
  /// that explains where rules come from.
  private var yoursSection: some View {
    Section {
      if userRules.isEmpty {
        if !isSearching {
          noteRow
        }
      } else {
        ForEach(matching(userRules)) { rule in
          yourRow(rule)
        }
      }
    } header: {
      sectionHeader(String(localized: "Yours · \(userRules.count)", bundle: .module))
    }
  }

  /// "Built in · N" with "Show all" once there are more rows than the preview
  /// shows. A search lists every match, so the link is not needed then.
  private var builtInSection: some View {
    let shown = isSearching
      ? matching(builtInRules)
      : RuleBuiltInPreview.visible(builtInRules, showAll: showsAllBuiltIn)
    let offersShowAll = !isSearching && !showsAllBuiltIn && builtInRules.count > RuleBuiltInPreview.rowLimit
    return Section {
      ForEach(shown) { rule in
        builtInRow(rule)
      }
    } header: {
      HStack(alignment: .center, spacing: NomiSpacing.xs) {
        sectionHeader(String(localized: "Built in · \(builtInRules.count)", bundle: .module))
        Spacer(minLength: NomiSpacing.xs)
        if offersShowAll {
          Button {
            showsAllBuiltIn = true
          } label: {
            Text("Show all", bundle: .module)
              .nomiTextStyle(.label)
              .foregroundStyle(NomiColor.navy)
              .frame(minHeight: NomiSpacing.minTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// The one note, after the built-in rules, when the user has rules of their own.
  private var noteSection: some View {
    Section {
      noteRow
    }
  }

  private var noteRow: some View {
    NomiStatusNote(
      String(localized: "Most of these are created for you when you turn on \"Always use this\" on a transaction.", bundle: .module),
      tone: .ok,
      systemImage: "sparkles"
    )
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
  }

  /// Shown in place of both sections when a search finds nothing.
  private var noMatchSection: some View {
    Section {
      NomiEmptyState(
        systemImage: "magnifyingglass",
        title: String(localized: "No rules for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”", bundle: .module),
        message: String(localized: "Rules are created when you turn on Always use this on a transaction.", bundle: .module)
      )
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  /// "Advanced: order and patterns", last, pushing the list of raw patterns.
  private var advancedSection: some View {
    Section {
      NavigationLink {
        RulesAdvancedScreen(ruleStore: ruleStore, categoryStore: categoryStore, accounts: accounts)
      } label: {
        HStack(spacing: NomiSpacing.xs) {
          Text("Advanced: order and patterns", bundle: .module)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Spacer(minLength: NomiSpacing.xs)
          Image(systemName: "chevron.right")
            .foregroundStyle(NomiColor.inkSecondary)
            .accessibilityHidden(true)
        }
        .frame(minHeight: NomiSpacing.rowMinHeight)
      }
      .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.dayHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  // MARK: - Rows

  /// A user rule. The row opens the editor; swipe deletes after the alert.
  private func yourRow(_ rule: NomiCore.Rule) -> some View {
    Button {
      editingRule = rule
    } label: {
      ruleRow(rule) {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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

  /// A built-in rule. Its switch is the only control; the rule is edited under
  /// "Order and patterns".
  private func builtInRow(_ rule: NomiCore.Rule) -> some View {
    let title = RuleDisplay.title(pattern: rule.pattern)
    return ruleRow(rule) {
      Toggle(
        String(localized: "Enable rule \(title)", bundle: .module),
        isOn: Binding(
          get: { rule.isEnabled },
          set: { setEnabled(rule, $0) }
        )
      )
      .labelsHidden()
      .tint(NomiColor.navy)
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
  }

  /// The text, the category tag and one trailing control. At accessibility
  /// sizes the tag moves under the text, so the title keeps its width and
  /// the control stays on the right.
  private func ruleRow<Trailing: View>(_ rule: NomiCore.Rule, @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          ruleText(rule)
          NomiTag(categoryName(for: rule))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ruleText(rule)
        NomiTag(categoryName(for: rule)).fixedSize()
      }
      trailing()
    }
    .padding(.vertical, 10)
  }

  /// The title and the scope line, the two lines every rule row shows.
  private func ruleText(_ rule: NomiCore.Rule) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(RuleDisplay.title(pattern: rule.pattern))
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      Text(scopeLine(for: rule))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // The text wins the width over the category tag at AX sizes; the tag keeps its word.
    .layoutPriority(1)
  }

  private func categoryName(for rule: NomiCore.Rule) -> String {
    categories.first(where: { $0.id == rule.categoryID })?.name ?? "Uncategorized"
  }

  private func scopeLine(for rule: NomiCore.Rule) -> String {
    RuleDisplay.scopeLine(rule.scope, accountName: accountLabel(_:))
  }

  /// "HDFC ••4471" for a scoped account. Nil when the account is no longer in
  /// the list, which `RuleDisplay.scopeLine` shows as "Unknown account".
  private func accountLabel(_ id: UUID) -> String? {
    accounts.first(where: { $0.id == id }).map {
      RuleDisplay.accountLabel(institution: $0.institution, lastFour: $0.lastFour)
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
}

#Preview("Auto-categorise — default, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeRulesContainer())
  .preferredColorScheme(.light)
}

#Preview("Auto-categorise — no rules of your own, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(rules: []), categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.light)
}

/// A container built locally to this file: a seeded rule, switched off, so the
/// built-in section shows a switch in its off position.
@MainActor
private func makeBuiltInDisabledContainer() -> ModelContainer {
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

#Preview("Auto-categorise — built in, switch off, light") {
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore())
  }
  .modelContainer(makeBuiltInDisabledContainer())
  .preferredColorScheme(.light)
}

/// Local, `Account`-inclusive container so a scoped rule shows its scope line.
@MainActor
private func makeScopedRuleContainer() -> (container: ModelContainer, accounts: [NomiCore.Account]) {
  let container = try! ModelContainer(
    for: Schema([NomiCore.Category.self, NomiCore.Rule.self, NomiCore.Account.self]),
    configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
  )
  let category = NomiCore.Category(name: "Eating out", symbolName: "fork.knife", paletteSlot: 1, isSystem: false, sortIndex: 0)
  let account = NomiCore.Account(displayName: "HDFC •• 4471", institution: "HDFC", lastFour: "4471", kindRaw: "bank")
  container.mainContext.insert(category)
  container.mainContext.insert(account)
  container.mainContext.insert(
    NomiCore.Rule(
      pattern: "*BLUE TOKAI*",
      categoryID: category.id,
      priority: 0,
      scope: RuleScope(direction: .debit, accountID: account.id, minAmountMinor: 100_00, maxAmountMinor: 2000_00)
    )
  )
  return (container, [account])
}

#Preview("Auto-categorise — yours with a scope, light") {
  let fixture = makeScopedRuleContainer()
  NavigationStack {
    RulesScreen(ruleStore: FakeRuleStore(), categoryStore: FakeCategoryStore(), accounts: fixture.accounts)
  }
  .modelContainer(fixture.container)
  .preferredColorScheme(.light)
}
