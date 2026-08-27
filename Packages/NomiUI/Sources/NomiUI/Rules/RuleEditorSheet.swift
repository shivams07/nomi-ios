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
  let rule: NomiCore.Rule?

  @Environment(\.dismiss) private var dismiss
  @State private var pattern: String
  @State private var categoryID: UUID?
  @State private var matchCount = 0
  @State private var errorMessage: String?

  init(ruleStore: RuleStore, categories: [NomiCore.Category], rule: NomiCore.Rule?) {
    self.ruleStore = ruleStore
    self.categories = categories
    self.rule = rule
    _pattern = State(initialValue: rule?.pattern ?? "")
    _categoryID = State(initialValue: rule?.categoryID ?? categories.first?.id)
  }

  private var isCreating: Bool { rule == nil }
  private var canSave: Bool { RuleFormGate.isValid(pattern: pattern, categoryID: categoryID) }

  var body: some View {
    NavigationStack {
      Form {
        Section("Pattern") {
          TextField("*MERCHANT*", text: $pattern)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
        }
        Section("Category") {
          Picker("Category", selection: $categoryID) {
            ForEach(categories) { category in
              Text(category.name).tag(Optional(category.id))
            }
          }
        }
        Section {
          Text(RuleMatchSummary.text(for: matchCount))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
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
      .onChange(of: pattern) { _, newValue in updateMatchCount(newValue) }
      .onAppear { updateMatchCount(pattern) }
    }
  }

  private func updateMatchCount(_ pattern: String) {
    matchCount = (try? ruleStore.preview(pattern: pattern)) ?? 0
  }

  private func save() {
    guard canSave, let categoryID else { return }
    do {
      if let rule {
        try ruleStore.update(rule.id, pattern: pattern, categoryID: categoryID)
      } else {
        try ruleStore.create(pattern: pattern, categoryID: categoryID)
      }
      dismiss()
    } catch {
      errorMessage = "Could not save rule."
    }
  }
}

#Preview("Rule editor — create, dark") {
  RuleEditorSheet(ruleStore: FakeRuleStore(), categories: EntryRulesPreviewSupport.makeCategories(), rule: nil)
    .preferredColorScheme(.dark)
}
