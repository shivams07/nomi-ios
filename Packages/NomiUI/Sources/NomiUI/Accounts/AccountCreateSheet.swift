import NomiCore
import NomiPreview
import SwiftUI

/// Create-only sheet for an account, `AccountRenameSheet`'s shape (Form in a
/// NavigationStack, Cancel/Save toolbar, Save disabled by a gate,
/// `errorMessage` section on throw) with three more fields. There is no edit
/// path here: `AccountStore` has no method to change an existing account's
/// institution, last four, or kind — only rename and archive.
struct AccountCreateSheet: View {
  let accountStore: AccountStore
  var onCreated: ((UUID) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var displayName = ""
  @State private var institution = ""
  @State private var lastFour = ""
  @State private var kindRaw = AccountKindOptions.defaultKind
  @State private var errorMessage: String?

  init(accountStore: AccountStore, onCreated: ((UUID) -> Void)? = nil) {
    self.accountStore = accountStore
    self.onCreated = onCreated
  }

  private var canSave: Bool {
    AccountCreateFormGate.isValid(displayName: displayName, lastFour: lastFour)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Account name", text: $displayName)
        }
        Section("Institution") {
          TextField("Institution", text: $institution)
        }
        Section("Last four digits") {
          TextField("e.g. 4471", text: $lastFour)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        }
        Section("Kind") {
          Picker("Kind", selection: $kindRaw) {
            ForEach(AccountKindOptions.all, id: \.self) { kind in
              Text(kind.capitalized).tag(kind)
            }
          }
          .pickerStyle(.segmented)
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
      .navigationTitle("New Account")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
        }
      }
    }
  }

  private func save() {
    guard canSave else { return }
    do {
      let created = try accountStore.create(
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
        lastFour: lastFour,
        kindRaw: kindRaw
      )
      onCreated?(created.id)
      dismiss()
    } catch {
      errorMessage = "Could not create account."
    }
  }
}

#Preview("Account create — empty, Save disabled, dark") {
  AccountCreateSheet(accountStore: FakeAccountStore(accounts: []))
    .preferredColorScheme(.dark)
}
