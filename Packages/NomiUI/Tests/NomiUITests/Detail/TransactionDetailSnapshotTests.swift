#if os(iOS)
import NomiCore
import NomiPreview
import SwiftUI
import UIKit
import XCTest
@testable import NomiUI

/// Renders the Transaction detail sheet at accessibility 3 into a PNG, for the S3a
/// device-free check (a hosted `layer.render`, not a simulator tap). It runs only
/// when `NOMI_SNAPSHOT_DIR` is set, so the ordinary suite skips it.
@MainActor
final class TransactionDetailSnapshotTests: XCTestCase {
  func testRendersTheSheetAtAccessibility3() throws {
    guard let directory = ProcessInfo.processInfo.environment["NOMI_SNAPSHOT_DIR"] else {
      throw XCTSkip("NOMI_SNAPSHOT_DIR is not set")
    }
    let transactions = PreviewData.transactions
    let row = try XCTUnwrap(
      transactions.first { $0.categoryID != nil && $0.merchantName != nil && !$0.isTransfer }
        ?? transactions.first)
    let view = TransactionDetailScreen(
      transactionID: row.id,
      transactionStore: FakeTransactionStore(transactions: transactions),
      editor: FakeTransactionEditor(transactions: transactions),
      categoryStore: FakeCategoryStore(),
      accountStore: FakeAccountStore()
    )
    .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
    .environment(\.nomiRuleStore, FakeRuleStore())
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)

    // Taller than a phone so the whole scroll content draws, the Delete row included.
    let size = CGSize(width: 402, height: 2600)
    let host = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.frame = window.bounds
    // Let the @Query and the onAppear reads settle before the layer is drawn.
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    host.view.layoutIfNeeded()

    let image = UIGraphicsImageRenderer(size: size).image { context in
      window.layer.render(in: context.cgContext)
    }
    let data = try XCTUnwrap(image.pngData())
    let url = URL(fileURLWithPath: directory).appendingPathComponent("detail-ax3.png")
    try data.write(to: url)
    XCTAssertGreaterThan(data.count, 10_000, "snapshot looks empty: \(url.path)")
  }
}
#endif
