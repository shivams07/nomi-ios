import NomiCore
import NomiPreview
import SwiftUI

/// The account edit sheet (AC, approved `AccountRename` artboard). Every field
/// `AccountStore.update` accepts, plus opening balance, in one grouped card.
/// Below it, the kind-dependent opening-balance footer (DEC-06) and "Tracked
/// since", then Archive and Delete as centred rows.
///
/// Archive and Delete do not confirm here. They hand off to `AccountsScreen`
/// through `onArchive` and `onDelete`, and the sheet dismisses. The screen
/// presents the existing confirmation once the sheet has gone, so there is one
/// copy of each confirmation. Unarchive has no confirmation, as in the row's
/// context menu, and runs here.
///
/// Save is disabled at 40% until `AccountEditFormGate` passes.
struct AccountRenameSheet: View {
  let accountStore: AccountStore
  let account: AccountSummary
  var onSaved: (() -> Void)?
  var onArchive: (() -> Void)?
  var onDelete: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var displayName: String
  @State private var institution: String
  @State private var lastFour: String
  @State private var kindRaw: String
  @State private var openingBalanceText: String
  @State private var errorMessage: String?

  init(
    accountStore: AccountStore,
    account: AccountSummary,
    onSaved: (() -> Void)? = nil,
    onArchive: (() -> Void)? = nil,
    onDelete: (() -> Void)? = nil
  ) {
    self.accountStore = accountStore
    self.account = account
    self.onSaved = onSaved
    self.onArchive = onArchive
    self.onDelete = onDelete
    _displayName = State(initialValue: account.displayName)
    _institution = State(initialValue: account.institution)
    _lastFour = State(initialValue: account.lastFour)
    _kindRaw = State(initialValue: account.kindRaw)
    _openingBalanceText = State(initialValue: AccountOpeningBalanceField.string(minor: account.openingBalanceMinor))
  }

  private var canSave: Bool {
    AccountEditFormGate.isValid(displayName: displayName, lastFour: lastFour, openingBalanceText: openingBalanceText)
  }

  private var hasActions: Bool {
    account.isArchived || onArchive != nil || onDelete != nil
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
          VStack(spacing: 0) {
            AccountFieldRow(label: "Name") {
              TextField("Name", text: $displayName, prompt: Text("Account name").foregroundStyle(NomiColor.placeholder))
                .accountFieldText()
            }
            AccountFieldRow(label: "Institution") {
              TextField("Institution", text: $institution, prompt: Text("Institution").foregroundStyle(NomiColor.placeholder))
                .accountFieldText()
            }
            AccountFieldRow(label: "Last four digits") {
              TextField("Last four digits", text: $lastFour, prompt: Text("e.g. 4471").foregroundStyle(NomiColor.placeholder))
                .accountFieldText()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            }
            AccountFieldRow(label: "Kind") {
              AccountKindControl(kindRaw: $kindRaw)
            }
            AccountFieldRow(label: "Opening balance", showsDivider: false) {
              TextField("Opening balance", text: $openingBalanceText, prompt: Text("e.g. 15000.00").foregroundStyle(NomiColor.placeholder))
                .accountFieldText()
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            }
          }
          .nomiCard(padding: EdgeInsets())

          footnotes

          if hasActions {
            actionsCard
          }

          if let errorMessage {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.horizontal, NomiSpacing.xxs)
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      .navigationTitle("Edit Account")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
        }
      }
    }
    .nomiSheet(detents: [.large])
  }

  /// The opening-balance footer for the kind currently selected in the form,
  /// so changing Kind changes the advice at once. Then "Tracked since", which
  /// shows how far back the tracked balance reaches (DEC-06).
  private var footnotes: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(AccountBalanceDisplay.openingBalanceFooter(kind: AccountKindOptions.kind(raw: kindRaw)))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
      if let since = TrackedBalanceCaption.sinceText(account.trackingSince) {
        Text("Tracked " + since)
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
      }
    }
    .padding(.horizontal, NomiSpacing.xxs)
  }

  private var actionsCard: some View {
    VStack(spacing: 0) {
      if account.isArchived {
        AccountActionRow(title: "Unarchive account", color: NomiColor.navy, showsDivider: onDelete != nil) {
          unarchive()
        }
      } else if let onArchive {
        AccountActionRow(title: "Archive account", color: NomiColor.navy, showsDivider: onDelete != nil) {
          onArchive()
          dismiss()
        }
      }
      if let onDelete {
        AccountActionRow(title: "Delete account", color: NomiColor.error, showsDivider: false) {
          onDelete()
          dismiss()
        }
      }
    }
    .nomiCard(padding: EdgeInsets())
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

  private func unarchive() {
    do {
      try accountStore.setArchived(account.id, false)
      onSaved?()
      dismiss()
    } catch {
      errorMessage = "Could not save account."
    }
  }
}

/// A centred action row in an account card: 52 pt high, 15 pt medium text,
/// with a hairline below when another row follows.
private struct AccountActionRow: View {
  let title: String
  let color: Color
  let showsDivider: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
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
  }
}

#Preview("Account edit — with opening balance, light") {
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
    ),
    onArchive: {},
    onDelete: {}
  )
  .preferredColorScheme(.light)
}

#Preview("Account edit — card, owed, light") {
  AccountRenameSheet(
    accountStore: FakeAccountStore(),
    account: AccountSummary(
      id: UUID(),
      displayName: "ICICI Credit Card",
      institution: "ICICI Bank",
      lastFour: "9012",
      kindRaw: "card",
      trackedBalanceMinor: -18_420_50,
      transactionCount: 18,
      trackingSince: Date(),
      isArchived: false,
      openingBalanceMinor: -18_420_00
    ),
    onArchive: {},
    onDelete: {}
  )
  .preferredColorScheme(.light)
}

#Preview("Account edit — no opening balance yet, light") {
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
    ),
    onArchive: {},
    onDelete: {}
  )
  .preferredColorScheme(.light)
}

#Preview("Account edit — archived, light") {
  AccountRenameSheet(
    accountStore: FakeAccountStore(),
    account: AccountSummary(
      id: UUID(),
      displayName: "Old Wallet",
      institution: "Paytm",
      lastFour: "",
      kindRaw: "wallet",
      trackedBalanceMinor: 0,
      transactionCount: 3,
      trackingSince: nil,
      isArchived: true
    ),
    onDelete: {}
  )
  .preferredColorScheme(.light)
}
