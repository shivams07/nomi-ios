import Foundation
import SwiftUI

/// The CSV file an export tap wrote. `Identifiable`, so `.sheet(item:)` opens
/// a fresh share sheet for each tap.
struct ReportsShareItem: Identifiable {
  let id = UUID()
  let url: URL
}

/// The CSV the share sheet is showing. Dismissing the sheet removes that file
/// and nothing else (R12b, Y1). Kept out of the view so the rule is testable.
struct ReportsShareCleanup {
  private(set) var shown: URL?

  mutating func show(_ url: URL) {
    shown = url
  }

  /// Removes the shown file, if there is one, and forgets it.
  mutating func dismiss() {
    if let shown {
      ReportsCSVExport.remove(shown)
    }
    shown = nil
  }
}

#if os(iOS)
import UIKit

/// `UIActivityViewController` for one exported CSV, presented from the Insights
/// export menu (R12b, Y1). On macOS the view is empty, so the package still
/// builds.
struct ReportsShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
struct ReportsShareSheet: View {
  let url: URL

  var body: some View {
    EmptyView()
  }
}
#endif
