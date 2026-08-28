import NomiCore
import SwiftUI

/// The column-mapping UI: which header goes to date/description/amount, an
/// optional reference column, how direction is derived, and the date format
/// string. Presented as a sheet over `ImportPreviewScreen` so "adjust
/// mapping" is an explicit extra step, not the default path when a format was
/// auto-detected.
struct ColumnMappingEditor: View {
  let headers: [String]
  @Binding var mapping: ColumnMapping
  @Environment(\.dismiss) private var dismiss

  private var canSave: Bool {
    ColumnMappingFormGate.isValid(mapping, headerCount: headers.count)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Columns") {
          columnPicker("Date", selection: $mapping.dateColumn)
          columnPicker("Description", selection: $mapping.descriptionColumn)
          columnPicker("Amount", selection: $mapping.amountColumn)
          referencePicker
        }
        Section("Direction") {
          directionPicker
        }
        Section("Date format") {
          TextField("dd/MM/yyyy", text: $mapping.dateFormat)
            .autocorrectionDisabled()
        }
      }
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle("Column Mapping")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .disabled(!canSave)
        }
      }
    }
  }

  private func columnPicker(_ label: String, selection: Binding<Int>) -> some View {
    Picker(label, selection: selection) {
      ForEach(headers.indices, id: \.self) { index in
        Text(headers[index]).tag(index)
      }
    }
  }

  private var referencePicker: some View {
    Picker("Reference", selection: Binding(
      get: { mapping.referenceColumn ?? -1 },
      set: { mapping.referenceColumn = $0 == -1 ? nil : $0 }
    )) {
      Text("None").tag(-1)
      ForEach(headers.indices, id: \.self) { index in
        Text(headers[index]).tag(index)
      }
    }
  }

  @ViewBuilder
  private var directionPicker: some View {
    Picker("Strategy", selection: strategyKindBinding) {
      Text("Signed amount").tag(DirectionStrategyKind.signedAmount)
      Text("Separate debit/credit columns").tag(DirectionStrategyKind.separateColumns)
      Text("Flag column").tag(DirectionStrategyKind.flagColumn)
    }
    switch mapping.directionStrategy {
    case .signedAmount:
      EmptyView()
    case .separateColumns(let debit, let credit):
      columnPicker("Debit column", selection: Binding(
        get: { debit },
        set: { mapping.directionStrategy = .separateColumns(debit: $0, credit: credit) }
      ))
      columnPicker("Credit column", selection: Binding(
        get: { credit },
        set: { mapping.directionStrategy = .separateColumns(debit: debit, credit: $0) }
      ))
    case .flagColumn(let index, let debitValues):
      columnPicker("Flag column", selection: Binding(
        get: { index },
        set: { mapping.directionStrategy = .flagColumn(index: $0, debitValues: debitValues) }
      ))
      TextField("Debit values, comma-separated", text: Binding(
        get: { debitValues.joined(separator: ", ") },
        set: { mapping.directionStrategy = .flagColumn(index: index, debitValues: $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
      ))
    }
  }

  private var strategyKindBinding: Binding<DirectionStrategyKind> {
    Binding(
      get: { DirectionStrategyKind(mapping.directionStrategy) },
      set: { newKind in
        switch newKind {
        case .signedAmount: mapping.directionStrategy = .signedAmount
        case .separateColumns: mapping.directionStrategy = .separateColumns(debit: 0, credit: min(1, max(headers.count - 1, 0)))
        case .flagColumn: mapping.directionStrategy = .flagColumn(index: 0, debitValues: ["DR"])
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

#Preview("Column mapping — signed amount, dark") {
  ColumnMappingEditor(
    headers: ["Date", "Narration", "Amount", "Reference"],
    mapping: .constant(ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: 3,
      directionStrategy: .signedAmount, dateFormat: "dd/MM/yyyy"
    ))
  )
  .preferredColorScheme(.dark)
}

#Preview("Column mapping — flag column, dark") {
  ColumnMappingEditor(
    headers: ["Date", "Narration", "Amount", "Type"],
    mapping: .constant(ColumnMapping(
      dateColumn: 0, descriptionColumn: 1, amountColumn: 2, referenceColumn: nil,
      directionStrategy: .flagColumn(index: 3, debitValues: ["DR"]), dateFormat: "dd/MM/yyyy"
    ))
  )
  .preferredColorScheme(.dark)
}
