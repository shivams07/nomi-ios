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

  @Query(sort: \NomiCore.Rule.priority) private var rules: [NomiCore.Rule]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingRule: NomiCore.Rule?
  @State private var isCreating = false

  public init(ruleStore: RuleStore, categoryStore: CategoryStore) {
    self.ruleStore = ruleStore
    self.categoryStore = categoryStore
  }

  public var body: some View {
    List {
      ForEach(rules) { rule in
        row(for: rule)
          .contentShape(Rectangle())
          .onTapGesture { editingRule = rule }
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
      RuleEditorSheet(ruleStore: ruleStore, categories: categories, rule: nil)
    }
    .sheet(item: $editingRule) { rule in
      RuleEditorSheet(ruleStore: ruleStore, categories: categories, rule: rule)
    }
  }

  private func row(for rule: NomiCore.Rule) -> some View {
    let categoryName = categories.first(where: { $0.id == rule.categoryID })?.name ?? "Uncategorized"
    return HStack(spacing: NomiSpacing.xs) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(NomiColor.textTertiary)
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(rule.pattern)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
        Text(categoryName)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer()
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      try? ruleStore.delete(rules[index].id)
    }
  }

  private func move(from source: IndexSet, to destination: Int) {
    let orderedIDs = RulesReorder.orderedIDs(current: rules.map(\.id), from: source, to: destination)
    try? ruleStore.reorder(orderedIDs)
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
