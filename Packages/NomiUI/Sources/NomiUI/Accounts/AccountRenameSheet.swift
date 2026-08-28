import NomiCore
import NomiPreview
import SwiftUI

/// Rename-only sheet for an account, same shape as `CategoryEditorSheet`:
/// empty/whitespace-only input disables Save rather than being persisted.
struct AccountRenameSheet: View {
  let accountStore: AccountStore
  let account: AccountSummary
  var onRenamed: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var errorMessage: String?

  init(accountStore: AccountStore, account: AccountSummary, onRenamed: (() -> Void)? = nil) {
    self.accountStore = accountStore
    self.account = account
    self.onRenamed = onRenamed
    _name = State(initialValue: account.displayName)
  }

  private var canSave: Bool { AccountRenameGate.isValid(name: name) }

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Account name", text: $name)
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
      .navigationTitle("Rename Account")
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
      try accountStore.rename(account.id, to: name)
      onRenamed?()
      dismiss()
    } catch {
      errorMessage = "Could not rename account."
    }
  }
}

#Preview("Account rename, dark") {
  AccountRenameSheet(
    accountStore: FakeAccountStore(),
    account: AccountSummary(
      id: UUID(),
      displayName: "HDFC •• 4471",
      institution: "HDFC Bank",
      lastFour: "4471",
      kindRaw: "bank",
      trackedBalanceMinor: 128_450_00,
      transactionCount: 42,
      trackingSince: Date(),
      isArchived: false
    )
  )
  .preferredColorScheme(.dark)
}
