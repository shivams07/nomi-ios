import SwiftUI

/// The open-source licence text the app ships, read from the bundled
/// `Licenses.txt` (S9b). Monospaced so each licence keeps its line layout.
public struct LicensesScreen: View {
  public init() {}

  public var body: some View {
    ScrollView {
      Group {
        if let text = AboutLogic.licencesText() {
          // One Text over the whole file draws nothing at AX3 and up, so the text
          // goes in blocks of whole lines (LicensesLogic). Each block is its own layer.
          // This is a VStack, not a LazyVStack: a lazy stack leaves the rows at a far
          // jump (bottom of the list at AX5) blank for good, because it never realises them.
          let blocks = LicensesLogic.blocks(for: text)
          VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
              Text(verbatim: blocks[index])
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(NomiColor.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
          }
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
