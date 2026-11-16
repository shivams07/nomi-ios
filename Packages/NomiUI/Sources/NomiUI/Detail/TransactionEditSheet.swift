import NomiCore
import SwiftUI

/// The Edit sheet on the transaction detail (S3b). It holds the amount, the
/// Spent / Income direction, the date, the description and the note, and writes
/// them on Save through `TransactionEditModel`. A transfer leg shows its direction
/// off, with the reason. Delete stays at the foot, as it was in the edit form
/// (the alert and the delete are the model's, the close is the detail's).
///
/// The fields are the ones the inline edit form had (same amount rules: R8 through
/// `EntryAmount`), plus the date and the direction.
struct TransactionEditSheet: View {
  @Bindable var model: TransactionEditModel
  let transactionStore: TransactionStore
  /// Called once Delete has removed the row, so the detail sheet closes with this one.
  let onDeleted: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var isDatePickerPresented = false
  @State private var isConfirmingDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.xs) {
          fieldLabel("Amount")
          fieldCard {
            HStack(spacing: NomiSpacing.xxs) {
              Text(currencySymbol)
                .font(Font.custom(NomiFont.interMedium, size: 22, relativeTo: .title2))
                .foregroundStyle(NomiColor.ink)
              TextField("0", text: $model.amountText)
                .font(Font.custom(NomiFont.interMedium, size: 22, relativeTo: .title2))
                .foregroundStyle(NomiColor.ink)
                .accessibilityLabel("Amount")
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onChange(of: model.amountText) { _, newValue in
                  model.amountDidChange(newValue)
                }
            }
          }
          directionControl
          fieldLabel("Date")
          dateRow
          fieldLabel("Description")
          fieldCard {
            TextField("Description", text: $model.descriptionText)
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.ink)
              .accessibilityLabel("Description")
          }
          fieldLabel("Note")
          fieldCard {
            TextField("Note", text: $model.noteText)
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.ink)
              .accessibilityLabel("Note")
          }
          NomiDestructiveRow(title: "Delete transaction") {
            isConfirmingDelete = true
          }
          .padding(.top, NomiSpacing.md)
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.top, NomiSpacing.xs)
        .padding(.bottom, NomiSpacing.screenGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(NomiColor.ground)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel")
              .nomiTextStyle(.navAction)
              .foregroundStyle(NomiColor.navy)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if model.save() {
              dismiss()
            }
          } label: {
            Text("Save")
              .nomiTextStyle(.navActionStrong)
              .foregroundStyle(NomiColor.navy)
          }
          .disabled(!model.canSave)
          .opacity(model.canSave ? 1 : 0.4)
        }
      }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("Edit transaction")
    }
    .nomiSheet(detents: [.large])
    .alert("Delete this transaction?", isPresented: $isConfirmingDelete) {
      Button("Delete", role: .destructive) { performDelete() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(model.deleteMessage)
    }
    .sheet(isPresented: $isDatePickerPresented) {
      DatePickerSheet(date: $model.date)
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
      presenting: model.errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  // MARK: - Direction

  /// Spent or income, as a segmented control. A transfer leg has no direction to
  /// change, so the control is off and its caption says how to change it.
  private var directionControl: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      NomiSegmented(
        [
          (value: Direction.debit, title: "Spent", systemImage: nil),
          (value: Direction.credit, title: "Income", systemImage: nil),
        ],
        selection: $model.direction,
        style: .onGround
      )
      .disabled(!model.isDirectionEditable)
      .opacity(model.isDirectionEditable ? 1 : 0.4)
      if let caption = model.directionCaption {
        Text(caption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, NomiSpacing.sm)
      }
    }
  }

  // MARK: - Date

  /// The date, as a row that opens the picker. The picker writes to the sheet's
  /// copy only; Save is what writes it.
  private var dateRow: some View {
    Button {
      isDatePickerPresented = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Text(NomiFormatters.dayMonthYear.string(from: model.date))
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .nomiCard(padding: EdgeInsets())
  }

  // MARK: - Fields

  /// U18: the amount's leading glyph is the row's own currency symbol, not a
  /// hardcoded "₹". `en_IN` stays the locale; only the symbol is read off the formatter.
  private var currencySymbol: String {
    guard model.currencyCode != "INR" else { return "₹" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencyCode = model.currencyCode
    return formatter.currencySymbol
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.inkDeep)
      .padding(.leading, NomiSpacing.xxs)
      .padding(.top, NomiSpacing.xxs)
  }

  private func fieldCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
  }

  // MARK: - Delete

  /// The store's delete, through the model. On success the detail closes with
  /// this sheet; on failure the error alert shows here.
  private func performDelete() {
    guard model.delete({ try transactionStore.delete($0) }) else { return }
    onDeleted()
  }
}
