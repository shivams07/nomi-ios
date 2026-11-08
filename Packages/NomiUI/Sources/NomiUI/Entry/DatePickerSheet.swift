import SwiftUI

// clt-harness: include

/// Presented only when the date chip is tapped, an optional step outside the
/// save path. Medium detent, "Done" only (DatePicker artboard). The graphical
/// picker stops at today, so a future date cannot be chosen. It sits in a
/// ScrollView so a medium detent never clips the month.
struct DatePickerSheet: View {
  @Binding var date: Date
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
          .datePickerStyle(.graphical)
          .labelsHidden()
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.vertical, NomiSpacing.xs)
      }
      .background(NomiColor.ground)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("Date")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .nomiSheet(detents: [.medium])
  }
}

#Preview("Date picker sheet · light") {
  DatePickerSheet(date: .constant(Date()))
    .preferredColorScheme(.light)
}
