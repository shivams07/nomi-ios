import NomiCore
import SwiftUI

/// The column-mapping sheet (IM; SIMP §3 item 21). Shape from the approved
/// `ColumnMapping` artboard: a native sheet with Cancel on the left, "Column
/// Mapping" centred and Save on the right, then cards under Columns, Direction
/// and Date format. Edits go to a draft and only Save writes them back, so
/// Cancel discards them.
struct ColumnMappingEditor: View {
  let headers: [String]
  @Binding var mapping: ColumnMapping
  @State private var draft: ColumnMapping
  @Environment(\.dismiss) private var dismiss

  init(headers: [String], mapping: Binding<ColumnMapping>) {
    self.headers = headers
    _mapping = mapping
    _draft = State(initialValue: mapping.wrappedValue)
  }

  private var canSave: Bool {
    ColumnMappingFormGate.isValid(draft, headerCount: headers.count)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          sectionLabel("Columns", first: true)
          card {
            pickerRow("Date", selection: $draft.dateColumn) {
              columnOptions
            }
            rowDivider
            pickerRow("Description", selection: $draft.descriptionColumn) {
              columnOptions
            }
            rowDivider
            pickerRow("Amount", selection: $draft.amountColumn) {
              columnOptions
            }
            rowDivider
            pickerRow("Reference", selection: referenceBinding) {
              Text("None").tag(-1)
              columnOptions
            }
          }

          sectionLabel("Direction")
          card {
            pickerRow("Strategy", selection: strategyKindBinding) {
              Text("Signed amount").tag(DirectionStrategyKind.signedAmount)
              Text("Separate debit/credit columns").tag(DirectionStrategyKind.separateColumns)
              Text("Flag column").tag(DirectionStrategyKind.flagColumn)
            }
            directionDetails
          }

          sectionLabel("Date format")
          card {
            TextField("dd/MM/yyyy", text: $draft.dateFormat)
              .autocorrectionDisabled()
              .nomiTextStyle(.rowBody)
              .foregroundStyle(NomiColor.ink)
              .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.top, NomiSpacing.sm)
        .padding(.bottom, NomiSpacing.lg)
      }
      .background(NomiColor.ground)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("Column Mapping")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            mapping = draft
            dismiss()
          }
          .disabled(!canSave)
        }
      }
    }
    .nomiSheet(detents: [.large])
  }

  // MARK: - Pieces

  private func sectionLabel(_ title: String, first: Bool = false) -> some View {
    Text(title)
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.inkDeep)
      .accessibilityAddTraits(.isHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, first ? 0 : NomiSpacing.md)
      .padding(.bottom, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard()
  }

  /// A label on the left, the current choice and its up-down chevron on the
  /// right (the menu picker draws both). Hit area is at least 52 pt.
  private func pickerRow<SelectionValue: Hashable, Options: View>(
    _ label: String,
    selection: Binding<SelectionValue>,
    @ViewBuilder options: () -> Options
  ) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Text(label)
        .nomiTextStyle(.rowBody)
        .foregroundStyle(NomiColor.ink)
      Spacer(minLength: NomiSpacing.xs)
      Picker(label, selection: selection) {
        options()
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .tint(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
  }

  private var columnOptions: some View {
    ForEach(headers.indices, id: \.self) { index in
      Text(headers[index]).tag(index)
    }
  }

  private var rowDivider: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var directionDetails: some View {
    switch draft.directionStrategy {
    case .signedAmount:
      EmptyView()
    case .separateColumns(let debit, let credit):
      rowDivider
      pickerRow("Debit column", selection: Binding(
        get: { debit },
        set: { draft.directionStrategy = .separateColumns(debit: $0, credit: credit) }
      )) {
        columnOptions
      }
      rowDivider
      pickerRow("Credit column", selection: Binding(
        get: { credit },
        set: { draft.directionStrategy = .separateColumns(debit: debit, credit: $0) }
      )) {
        columnOptions
      }
    case .flagColumn(let index, let debitValues):
      rowDivider
      pickerRow("Flag column", selection: Binding(
        get: { index },
        set: { draft.directionStrategy = .flagColumn(index: $0, debitValues: debitValues) }
      )) {
        columnOptions
      }
      rowDivider
      TextField("Debit values, comma-separated", text: Binding(
        get: { debitValues.joined(separator: ", ") },
        set: { draft.directionStrategy = .flagColumn(index: index, debitValues: $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
      ))
      .nomiTextStyle(.rowBody)
      .foregroundStyle(NomiColor.ink)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
    }
  }

  // MARK: - Bindings into the draft

  private var referenceBinding: Binding<Int> {
    Binding(
      get: { draft.referenceColumn ?? -1 },
      set: { draft.referenceColumn = $0 == -1 ? nil : $0 }
    )
  }

  private var strategyKindBinding: Binding<DirectionStrategyKind> {
    Binding(
      get: { DirectionStrategyKind(draft.directionStrategy) },
      set: { newKind in
        switch newKind {
        case .signedAmount: draft.directionStrategy = .signedAmount
        case .separateColumns: draft.directionStrategy = .separateColumns(debit: 0, credit: min(1, max(headers.count - 1, 0)))
        case .flagColumn: draft.directionStrategy = .flagColumn(index: 0, debitValues: ["DR"])
        }
      }
    )
  }
}

enum DirectionStrategyKind: Hashable {
  case signedAmount, separateColumns, flagColumn

  init(_ strategy: DirectionStrategy) {
    switch strategy {
    case .signedAmount: self = .signedAmount
    case .separateColumns: self = .separateColumns
    case .flagColumn: self = .flagColumn
    }
  }
}

#Preview("Column mapping — signed amount") {
  ColumnMappingEditor(
    headers: ["Date", "Narration", "Amount", "Reference"],
    mapping: .constant(ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: 3,
      directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
    ))
  )
}

#Preview("Column mapping — flag column") {
  ColumnMappingEditor(
    headers: ["Date", "Narration", "Amount", "Type"],
    mapping: .constant(ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
      directionStrategy: .flagColumn(index: 3, debitValues: ["DR"]), dateFormat: "dd/MM/yyyy"
    ))
  )
}
