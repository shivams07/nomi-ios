import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// One component, two consumers — the review queue and the entry sheet, both
/// landing in units that come after this one and both consuming this file.
/// Reads the live account list through `@Query`, same read/write asymmetry
/// as `CategoryPickerSheet`; writes (creating an account) still go through
/// `AccountStore`.
///
/// Not `@Binding var selection` like `CategoryPickerSheet`: the two
/// consumers do genuinely different things on selection (one calls
/// `setAccount` on a store, the other assigns to local `@State`), and a
/// `Binding` whose setter secretly writes to a store is the kind of
/// indirection that reads as a bug six months later.
struct AccountPickerSheet: View {
  /// Present only when the caller can offer account creation. `nil` in the
  /// entry sheet, which points at the Accounts screen instead.
  let accountStore: AccountStore?
  let selection: UUID?
  /// `nil` == "Unassigned".
  let onSelect: (UUID?) -> Void

  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false

  var body: some View {
    NavigationStack {
      List {
        unassignedRow
        ForEach(accounts) { account in
          row(for: account)
        }
        if accounts.isEmpty {
          emptyStateRow
        }
      }
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle("Account")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .sheet(isPresented: $isCreating) {
        if let accountStore {
          AccountCreateSheet(accountStore: accountStore) { newID in
            onSelect(newID)
            dismiss()
          }
        }
      }
    }
  }

  private var unassignedRow: some View {
    Button {
      onSelect(nil)
      dismiss()
    } label: {
      HStack {
        Text("Unassigned")
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
        Spacer()
        if selection == nil {
          Image(systemName: "checkmark")
            .foregroundStyle(NomiColor.accent)
        }
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  private func row(for account: NomiCore.Account) -> some View {
    Button {
      onSelect(account.id)
      dismiss()
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(account.displayName)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
          Text("\(account.institution) •• \(account.lastFour)")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
        Spacer()
        if selection == account.id {
          Image(systemName: "checkmark")
            .foregroundStyle(NomiColor.accent)
        }
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  @ViewBuilder
  private var emptyStateRow: some View {
    if accountStore != nil {
      Button {
        isCreating = true
      } label: {
        Label("New Account", systemImage: "plus")
          .foregroundStyle(NomiColor.accent)
      }
      .listRowBackground(NomiColor.surfaceRaised)
    } else {
      Text("Create an account from the Accounts screen first.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
        .listRowBackground(NomiColor.surfaceRaised)
    }
  }
}

/// Preview-only `ModelContainer` scaffolding, same "fresh container per
/// preview" convention as `EntryRulesPreviewSupport` — kept local to this
/// file since this unit must not edit `Entry/**` or `NomiPreview`.
private enum AccountPickerPreviewSupport {
  @MainActor
  static func makeContainer(seed: [NomiCore.Account]) -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Account.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    for account in seed {
      container.mainContext.insert(account)
    }
    return container
  }
}

#Preview("Account picker — populated, dark") {
  AccountPickerSheet(accountStore: FakeAccountStore(), selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: [
      NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4821"),
      NomiCore.Account(displayName: "ICICI Credit Card", institution: "ICICI Bank", lastFour: "9034"),
    ]))
    .preferredColorScheme(.dark)
}

#Preview("Account picker — zero accounts, create button visible, dark") {
  AccountPickerSheet(accountStore: FakeAccountStore(accounts: []), selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: []))
    .preferredColorScheme(.dark)
}

#Preview("Account picker — zero accounts, no create, dark") {
  AccountPickerSheet(accountStore: nil, selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: []))
    .preferredColorScheme(.dark)
}
