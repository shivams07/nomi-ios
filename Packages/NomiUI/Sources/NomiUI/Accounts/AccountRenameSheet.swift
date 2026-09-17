import NomiCore
import NomiPreview
import SwiftUI

/// The account edit sheet — every field `AccountStore.update` accepts, plus
/// opening balance. Named `AccountRenameSheet` still: per the design doc,
/// renaming the type here is churn for nothing now that it edits every
/// field, not just the name. Same shape as `AccountCreateSheet` (Form in a
/// NavigationStack, Cancel/Save toolbar, Save disabled by a gate,
/// `errorMessage` section on throw) with one more field: opening balance,
/// which `AccountCreateSheet` has no equivalent of because an account has no
/// opening balance to seed until it already exists.
struct AccountRenameSheet: View {
  let accountStore: AccountStore
  let account: AccountSummary
  var onSaved: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var displayName: String
  @State private var institution: String
  @State private var lastFour: String
  @State private var kindRaw: String
  @State private var openingBalanceText: String
  @State private var errorMessage: String?

  init(accountStore: AccountStore, account: AccountSummary, onSaved: (() -> Void)? = nil) {
    self.accountStore = accountStore
    self.account = account
    self.onSaved = onSaved
    _displayName = State(initialValue: account.displayName)
    _institution = State(initialValue: account.institution)
    _lastFour = State(initialValue: account.lastFour)
    _kindRaw = State(initialValue: account.kindRaw)
    _openingBalanceText = State(initialValue: AccountOpeningBalanceField.string(minor: account.openingBalanceMinor))
  }

  private var canSave: Bool {
    AccountEditFormGate.isValid(displayName: displayName, lastFour: lastFour, openingBalanceText: openingBalanceText)
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
        Section {
          TextField("e.g. 15000.00", text: $openingBalanceText)
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            #endif
        } header: {
          Text("Opening balance")
        } footer: {
          Text("What this account held before Nomi started tracking it. Leave blank if you don't know.")
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
      .navigationTitle("Edit Account")
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
      try accountStore.update(
        account.id,
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
        lastFour: lastFour,
        kindRaw: kindRaw,
        openingBalanceMinor: AccountOpeningBalanceField.minorUnits(from: openingBalanceText)
      )
      onSaved?()
      dismiss()
    } catch {
      errorMessage = "Could not save account."
    }
  }
}

#Preview("Account edit — with opening balance, dark") {
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
      isArchived: false,
      openingBalanceMinor: 50_000_00
    )
  )
  .preferredColorScheme(.dark)
}

#Preview("Account edit — no opening balance yet, dark") {
  AccountRenameSheet(
    accountStore: FakeAccountStore(),
    account: AccountSummary(
      id: UUID(),
      displayName: "New Savings",
      institution: "HDFC Bank",
      lastFour: "9911",
      kindRaw: "bank",
      trackedBalanceMinor: 0,
      transactionCount: 0,
      trackingSince: nil,
      isArchived: false
    )
  )
  .preferredColorScheme(.dark)
}
