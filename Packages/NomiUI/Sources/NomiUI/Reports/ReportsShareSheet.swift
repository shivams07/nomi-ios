import Foundation
import SwiftUI

/// The CSV file an export tap wrote. `Identifiable`, so `.sheet(item:)` opens
/// a fresh share sheet for each tap.
struct ReportsShareItem: Identifiable {
  let id = UUID()
  let url: URL
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
