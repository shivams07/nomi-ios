import SwiftUI

/// Presented only when the date chip is tapped — an EXTRA, optional step
/// outside the two-tap save path, never the default route to Save.
struct DatePickerSheet: View {
  @Binding var date: Date
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
        .datePickerStyle(.graphical)
        .padding(NomiSpacing.screenGutter)
        .background(NomiColor.surfaceCanvas)
        .navigationTitle("Date")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
  }
}

#Preview("Date picker sheet, dark") {
  DatePickerSheet(date: .constant(Date()))
    .preferredColorScheme(.dark)
}
