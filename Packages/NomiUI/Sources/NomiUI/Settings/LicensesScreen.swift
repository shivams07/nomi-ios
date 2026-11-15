import SwiftUI

/// The open-source licence text the app ships, read from the bundled
/// `Licenses.txt` (S9b). Monospaced so each licence keeps its line layout.
public struct LicensesScreen: View {
  public init() {}

  public var body: some View {
    ScrollView {
      Group {
        if let text = AboutLogic.licencesText() {
          Text(verbatim: text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(NomiColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        } else {
          Text("The licence text could not be loaded.", bundle: .module)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.sm)
    }
    .background(NomiColor.ground)
    .navigationTitle(String(localized: "Open-source licences", bundle: .module))
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

#Preview("Licences, light") {
  NavigationStack {
    LicensesScreen()
  }
  .preferredColorScheme(.light)
}
