import NomiCore
import NomiPreview
import SwiftUI

/// Create-only sheet for an account (AC, approved `AccountCreate` artboard).
/// One grouped card of label-and-field rows (Name, Institution, Last four
/// digits, Kind), with Cancel and Save in the bar. Save is disabled at 40%
/// until `AccountCreateFormGate` passes. There is no edit path here:
/// `AccountStore` has no method to change an existing account's institution,
/// last four, or kind, only rename, archive and delete.
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
            AccountFieldRow(label: "Kind", showsDivider: false) {
              AccountKindControl(kindRaw: $kindRaw)
            }
          }
          .nomiCard(padding: EdgeInsets())

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
      .navigationTitle("New Account")
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

/// One label-and-field row inside an account card: a 124 pt label on the
/// left, the field on the right, at least 52 pt high, with a hairline below
/// unless it is the card's last row. Shared with `AccountRenameSheet`.
struct AccountFieldRow<Field: View>: View {
  let label: String
  let showsDivider: Bool
  let field: Field

  init(label: String, showsDivider: Bool = true, @ViewBuilder field: () -> Field) {
    self.label = label
    self.showsDivider = showsDivider
    self.field = field()
  }

  var body: some View {
    HStack(spacing: NomiSpacing.cardGap) {
      Text(label)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
        .frame(width: 124, alignment: .leading)
      field
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(minHeight: NomiSpacing.rowMinHeight)
    .overlay(alignment: .bottom) {
      if showsDivider {
        Rectangle()
          .fill(NomiColor.separator)
          .frame(height: 1)
      }
    }
  }
}

extension View {
  /// Text in an account row: 15 pt regular ink, right-aligned, 44 pt high
  /// (the field's hit height). Shared by the create and edit sheets.
  func accountFieldText() -> some View {
    self
      .nomiTextStyle(.rowBody)
      .foregroundStyle(NomiColor.ink)
      .multilineTextAlignment(.trailing)
      .frame(minHeight: NomiSpacing.minTarget)
  }
}

/// The Kind control: three segments in a tinted 44 pt track. The selected
/// segment is a white card with ink text, as the approved Accounts artboards
/// draw it. The Entry direction toggle is navy; this control is not.
struct AccountKindControl: View {
  @Binding var kindRaw: String

  var body: some View {
    HStack(spacing: 2) {
      ForEach(AccountKindOptions.all, id: \.self) { kind in
        segment(kind)
      }
    }
    .padding(2)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(NomiColor.separator)
    )
  }

  private func segment(_ kind: String) -> some View {
    let isSelected = kind == kindRaw
    return Button {
      kindRaw = kind
    } label: {
      Text(kind.capitalized)
        .nomiTextStyle(isSelected ? .chipSelected : .chip)
        .foregroundStyle(isSelected ? NomiColor.ink : NomiColor.inkDeep)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(NomiColor.card)
              .shadow(color: NomiColor.inkDeep.opacity(0.12), radius: 1, x: 0, y: 1)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

#Preview("Account create — empty, Save disabled, light") {
  AccountCreateSheet(accountStore: FakeAccountStore(accounts: []))
    .preferredColorScheme(.light)
}
