import SwiftUI

/// About/version row (U7, v5 addition).
public struct AboutScreen: View {
  public init() {}

  public var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text("Nomi")
            .nomiTextStyle(.title)
            .foregroundStyle(NomiColor.textPrimary)
          Text("Version \(NomiUIModule.version)")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        }
        .padding(.vertical, NomiSpacing.xs)
      }
      Section {
        Text("Your transactions and mail credentials never leave your device except to sync between your own devices via iCloud.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("About")
  }
}

#Preview("About, dark") {
  NavigationStack {
    AboutScreen()
  }
  .preferredColorScheme(.dark)
}
