import Foundation
import SwiftUI

/// The CSV file an export tap wrote. `Identifiable`, so `.sheet(item:)` opens
/// a fresh share sheet for each tap.
struct ReportsShareItem: Identifiable {
  let id = UUID()
  let url: URL
}

/// The CSV the share sheet is showing. When SwiftUI clears the sheet's item on
/// dismissal, or the item is replaced, the previous file is removed (R12b, Y1).
/// The sheet's binding does the removing, so no `onDismiss` closure can forget it.
struct ReportsShareState {
  private var current: ReportsShareItem?

  var item: ReportsShareItem? {
    get { current }
    set {
      if let old = current, old.id != newValue?.id {
        ReportsCSVExport.remove(old.url)
      }
      current = newValue
    }
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
