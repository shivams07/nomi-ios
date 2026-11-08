import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// One component, two consumers: the transaction detail sheet and the entry
/// sheet. Reads the live account list through `@Query`, same read/write
/// asymmetry as `CategoryPickerSheet`; writes (creating an account) still go
/// through `AccountStore`.
///
/// Not `@Binding var selection` like `CategoryPickerSheet`: the two consumers
/// do genuinely different things on selection (one calls `setAccount` on a
/// store, the other assigns to local `@State`), and a `Binding` whose setter
/// secretly writes to a store is the kind of indirection that reads as a bug
/// six months later.
///
/// Medium detent, Cancel only, and a row tap commits (AC, approved
/// `AccountPicker` artboard). The rows sit in one grouped card.
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
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
          VStack(spacing: 0) {
            unassignedRow
            ForEach(accounts) { account in
              row(for: account)
            }
            if accounts.isEmpty {
              emptyStateRow
            }
          }
          .nomiCard(padding: EdgeInsets())
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      .navigationTitle("Account")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
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
    .nomiSheet(detents: [.medium])
  }

  /// Always followed by another row (an account or the empty-state row), so
  /// it always carries a divider.
  private var unassignedRow: some View {
    choiceRow(
      title: "Unassigned",
      subtitle: nil,
      isSelected: selection == nil,
      showsDivider: true
    ) {
      onSelect(nil)
      dismiss()
    }
  }

  private func row(for account: NomiCore.Account) -> some View {
    choiceRow(
      title: account.displayName,
      subtitle: subtitle(for: account),
      isSelected: selection == account.id,
      showsDivider: account.id != accounts.last?.id
    ) {
      onSelect(account.id)
      dismiss()
    }
  }

  /// "HDFC Bank •• 4471". A wallet with no last four shows the institution alone.
  private func subtitle(for account: NomiCore.Account) -> String? {
    if account.lastFour.isEmpty {
      return account.institution.isEmpty ? nil : account.institution
    }
    return "\(account.institution) •• \(account.lastFour)"
  }

  private func choiceRow(
    title: String,
    subtitle: String?,
    isSelected: Bool,
    showsDivider: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xs) {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text(title)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.ink)
          if let subtitle {
            Text(subtitle)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.inkSecondary)
          }
        }
        Spacer(minLength: NomiSpacing.xs)
        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(NomiColor.navy)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, NomiSpacing.sm)
      .padding(.vertical, NomiSpacing.xs)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        if showsDivider {
          Rectangle()
            .fill(NomiColor.separator)
            .frame(height: 1)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  @ViewBuilder
  private var emptyStateRow: some View {
    if accountStore != nil {
      Button {
        isCreating = true
      } label: {
        HStack(spacing: NomiSpacing.xs) {
          Image(systemName: "plus")
          Text("New Account")
            .nomiTextStyle(.body)
          Spacer(minLength: 0)
        }
        .foregroundStyle(NomiColor.navy)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, NomiSpacing.sm)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      Text("Create an account from the Accounts screen first.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, NomiSpacing.sm)
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

#Preview("Account picker — populated, light") {
  AccountPickerSheet(accountStore: FakeAccountStore(), selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: [
      NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4471"),
      NomiCore.Account(displayName: "ICICI Credit Card", institution: "ICICI Bank", lastFour: "9012", kindRaw: "card"),
    ]))
    .preferredColorScheme(.light)
}

#Preview("Account picker — zero accounts, create button visible, light") {
  AccountPickerSheet(accountStore: FakeAccountStore(accounts: []), selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: []))
    .preferredColorScheme(.light)
}

#Preview("Account picker — zero accounts, no create, light") {
  AccountPickerSheet(accountStore: nil, selection: nil, onSelect: { _ in })
    .modelContainer(AccountPickerPreviewSupport.makeContainer(seed: []))
    .preferredColorScheme(.light)
}
